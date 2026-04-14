package handlers

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// upgrader allows all origins in development. Tighten CheckOrigin for production.
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// broadcaster represents a Van Staff POS connection sending state.
type broadcaster struct {
	conn     *websocket.Conn
	userID   string
	userName string
}

// watcher represents a Super Admin connection receiving state.
type watcher struct {
	conn         *websocket.Conn
	connID       string
	targetUserID string
}

// PosMirrorHub manages all broadcaster and watcher connections.
type PosMirrorHub struct {
	mu           sync.RWMutex
	broadcasters map[string]*broadcaster // keyed by userID
	watchers     map[string]*watcher     // keyed by connID (random)
	stateCache   map[string][]byte       // latest pos_state per userID
}

func newPosMirrorHub() *PosMirrorHub {
	return &PosMirrorHub{
		broadcasters: make(map[string]*broadcaster),
		watchers:     make(map[string]*watcher),
		stateCache:   make(map[string][]byte),
	}
}

// onlineList returns the current list of online broadcasters.
func (h *PosMirrorHub) onlineList() []map[string]string {
	h.mu.RLock()
	defer h.mu.RUnlock()
	list := make([]map[string]string, 0, len(h.broadcasters))
	for _, b := range h.broadcasters {
		list = append(list, map[string]string{"id": b.userID, "name": b.userName})
	}
	return list
}

// sendOnlineList sends the online_list message to a single watcher connection.
func (h *PosMirrorHub) sendOnlineList(conn *websocket.Conn) {
	msg := map[string]interface{}{
		"type":         "online_list",
		"broadcasters": h.onlineList(),
	}
	data, _ := json.Marshal(msg)
	_ = conn.WriteMessage(websocket.TextMessage, data)
}

// broadcastOnlineListToWatchers sends updated online_list to all watchers.
func (h *PosMirrorHub) broadcastOnlineListToWatchers() {
	msg := map[string]interface{}{
		"type":         "online_list",
		"broadcasters": h.onlineList(),
	}
	data, _ := json.Marshal(msg)
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, w := range h.watchers {
		_ = w.conn.WriteMessage(websocket.TextMessage, data)
	}
}

// forwardToWatchers sends a pos_state update to watchers targeting the given userID.
func (h *PosMirrorHub) forwardToWatchers(userID string, enriched []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, w := range h.watchers {
		if w.targetUserID == userID {
			_ = w.conn.WriteMessage(websocket.TextMessage, enriched)
		}
	}
}

// PosMirrorHandler handles WebSocket upgrade and lifecycle for the POS mirror feature.
type PosMirrorHandler struct {
	hub      *PosMirrorHub
	sessions repository.SessionRepository
	users    repository.UserRepository
}

func NewPosMirrorHandler(sessions repository.SessionRepository, users repository.UserRepository) *PosMirrorHandler {
	return &PosMirrorHandler{
		hub:      newPosMirrorHub(),
		sessions: sessions,
		users:    users,
	}
}

// HandleWS upgrades the HTTP connection to WebSocket, authenticates the token,
// and dispatches the connection to broadcaster or watcher logic.
func (h *PosMirrorHandler) HandleWS(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_token"})
		return
	}

	ctx := c.Request.Context()
	session, err := h.sessions.GetValidByID(ctx, token, c.ClientIP(), time.Now().UTC())
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid_token"})
		return
	}

	user, err := h.users.GetByID(ctx, session.UserID)
	if err != nil || !user.IsActive {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_not_found"})
		return
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	switch user.RoleID {
	case "role.van_staff", "role.cashier":
		h.runBroadcaster(conn, user)
	case "role.admin", "role.hq_manager":
		h.runWatcher(conn, user)
	default:
		_ = conn.Close()
	}
}

// runBroadcaster registers a Van Staff connection and forwards its state updates.
func (h *PosMirrorHandler) runBroadcaster(conn *websocket.Conn, user *repository.User) {
	b := &broadcaster{conn: conn, userID: user.ID, userName: user.Name}

	h.hub.mu.Lock()
	h.hub.broadcasters[user.ID] = b
	h.hub.mu.Unlock()

	h.hub.broadcastOnlineListToWatchers()

	defer func() {
		h.hub.mu.Lock()
		delete(h.hub.broadcasters, user.ID)
		delete(h.hub.stateCache, user.ID)
		h.hub.mu.Unlock()
		_ = conn.Close()
		h.hub.broadcastOnlineListToWatchers()
	}()

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}

		// Parse to verify it's a pos_state message
		var parsed map[string]interface{}
		if err := json.Unmarshal(msg, &parsed); err != nil {
			continue
		}
		if parsed["type"] != "pos_state" {
			continue
		}

		// Enrich with sender identity
		parsed["vanStaffId"] = user.ID
		parsed["vanStaffName"] = user.Name
		enriched, err := json.Marshal(parsed)
		if err != nil {
			continue
		}

		// Cache and forward
		h.hub.mu.Lock()
		h.hub.stateCache[user.ID] = enriched
		h.hub.mu.Unlock()

		h.hub.forwardToWatchers(user.ID, enriched)
	}
}

// runWatcher registers a Super Admin connection and handles watch/get_online requests.
func (h *PosMirrorHandler) runWatcher(conn *websocket.Conn, user *repository.User) {
	connID := user.ID + "-" + time.Now().Format("150405.000")
	w := &watcher{conn: conn, connID: connID, targetUserID: ""}

	h.hub.mu.Lock()
	h.hub.watchers[connID] = w
	h.hub.mu.Unlock()

	// Send current online list immediately on connect
	h.hub.sendOnlineList(conn)

	defer func() {
		h.hub.mu.Lock()
		delete(h.hub.watchers, connID)
		h.hub.mu.Unlock()
		_ = conn.Close()
	}()

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}

		var req map[string]interface{}
		if err := json.Unmarshal(msg, &req); err != nil {
			continue
		}

		switch req["type"] {
		case "get_online":
			h.hub.sendOnlineList(conn)

		case "watch":
			targetID, _ := req["targetUserId"].(string)
			h.hub.mu.Lock()
			w.targetUserID = targetID
			h.hub.mu.Unlock()

			// Send cached state immediately if available
			h.hub.mu.RLock()
			cached := h.hub.stateCache[targetID]
			h.hub.mu.RUnlock()
			if cached != nil {
				_ = conn.WriteMessage(websocket.TextMessage, cached)
			}
		}
	}
}
