package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"backend/internal/config"
	"backend/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// broadcaster represents a Van Staff POS connection sending state.
type broadcaster struct {
	conn     *websocket.Conn
	userID   string
	userName string
	branchID string
	posID    string
	posKey   string
}

// watcher represents a Super Admin connection receiving state.
type watcher struct {
	conn         *websocket.Conn
	connID       string
	targetUserID string
}

// customerDisplay represents the always-open browser on the second monitor.
type customerDisplay struct {
	conn   *websocket.Conn
	connID string
	posKey string
}

// PosMirrorHub manages all broadcaster and watcher connections.
type PosMirrorHub struct {
	mu               sync.RWMutex
	broadcasters     map[string]*broadcaster     // keyed by userID
	watchers         map[string]*watcher         // keyed by connID (random)
	customerDisplays map[string]*customerDisplay // keyed by connID
	stateCache       map[string][]byte           // latest pos_state per userID
	posStateCache    map[string][]byte           // latest pos_state per branchID:posID
}

func newPosMirrorHub() *PosMirrorHub {
	return &PosMirrorHub{
		broadcasters:     make(map[string]*broadcaster),
		watchers:         make(map[string]*watcher),
		customerDisplays: make(map[string]*customerDisplay),
		stateCache:       make(map[string][]byte),
		posStateCache:    make(map[string][]byte),
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

func posMirrorKey(branchID, posID string) string {
	return branchID + ":" + posID
}

func (h *PosMirrorHub) forwardToCustomerDisplays(posKey string, enriched []byte) {
	if posKey == ":" || posKey == "" {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, display := range h.customerDisplays {
		if display.posKey == posKey {
			_ = display.conn.WriteMessage(websocket.TextMessage, enriched)
		}
	}
}

func (h *PosMirrorHub) publishPOSState(posKey string, state []byte) {
	if posKey == ":" || posKey == "" {
		return
	}
	h.mu.Lock()
	h.posStateCache[posKey] = state
	h.mu.Unlock()
	h.forwardToCustomerDisplays(posKey, state)
}

// PosMirrorHandler handles WebSocket upgrade and lifecycle for the POS mirror feature.
type PosMirrorHandler struct {
	hub            *PosMirrorHub
	sessions       repository.SessionRepository
	users          repository.UserRepository
	pos            repository.POSRepository
	cfg            config.Config
	allowedOrigins []string
}

func NewPosMirrorHandler(sessions repository.SessionRepository, users repository.UserRepository, pos repository.POSRepository, cfg config.Config) *PosMirrorHandler {
	return &PosMirrorHandler{
		hub:            newPosMirrorHub(),
		sessions:       sessions,
		users:          users,
		pos:            pos,
		cfg:            cfg,
		allowedOrigins: parseOriginList(cfg.CORSAllowedOrigins),
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

	conn, err := h.upgrade(c)
	if err != nil {
		return
	}

	switch user.RoleID {
	case "role.van_staff", "role.cashier":
		h.runBroadcaster(conn, user, session.BranchID, session.POSID)
	case "role.admin", "role.hq_manager":
		h.runWatcher(conn, user)
	default:
		_ = conn.Close()
	}
}

// HandleCustomerDisplayWS upgrades a customer-display browser connection.
// It uses POS credentials instead of a cashier session so the second-monitor
// kiosk can stay open without logging in.
func (h *PosMirrorHandler) HandleCustomerDisplayWS(c *gin.Context) {
	branchID := c.Query("branchId")
	posID := c.Query("posId")
	posSecret := c.Query("posSecret")
	if branchID == "" || posID == "" || posSecret == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_customer_display_credentials"})
		return
	}

	pos, err := h.pos.GetByID(c.Request.Context(), posID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid_pos"})
		return
	}
	if !pos.IsActive || pos.BranchID != branchID || pos.POSSecret != posSecret {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid_pos_credentials"})
		return
	}

	conn, err := h.upgrade(c)
	if err != nil {
		return
	}
	h.runCustomerDisplay(conn, posMirrorKey(branchID, posID))
}

// TestState publishes a synthetic state to customer displays for the caller's
// POS session. It is useful on the Windows POS before running a real sale.
func (h *PosMirrorHandler) TestState(c *gin.Context) {
	branchIDVal, branchOK := c.Get("branch_id")
	posIDVal, posOK := c.Get("pos_id")
	branchID, _ := branchIDVal.(string)
	posID, _ := posIDVal.(string)
	if !branchOK || !posOK || branchID == "" || posID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing_pos_context"})
		return
	}

	state := map[string]interface{}{
		"type":   "pos_state",
		"billId": "DISPLAY-TEST",
		"items": []map[string]interface{}{
			{"partCode": "TEST001", "partName": "Customer display test item", "qty": 1, "unitPrice": 10.0, "lineTotal": 10.0},
		},
		"subtotal":       10.0,
		"discount":       0.0,
		"tax":            0.65,
		"total":          10.0,
		"member":         nil,
		"taxRate":        7.0,
		"isAwaitingCash": false,
		"cashAmount":     0.0,
		"isAwaitingQr":   false,
		"showThankYou":   false,
		"activeDialog":   "receipt",
		"lastBarcode":    "TEST001",
		"dialogState":    nil,
		"lastAction":     "test_state",
	}

	if c.Request.ContentLength > 0 {
		var req map[string]interface{}
		if err := c.ShouldBindJSON(&req); err == nil && len(req) > 0 {
			for k, v := range req {
				state[k] = v
			}
			state["type"] = "pos_state"
		}
	}

	data, err := json.Marshal(state)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_encode_state"})
		return
	}
	h.hub.publishPOSState(posMirrorKey(branchID, posID), data)
	c.JSON(http.StatusOK, gin.H{"ok": true, "branchId": branchID, "posId": posID})
}

func (h *PosMirrorHandler) upgrade(c *gin.Context) (*websocket.Conn, error) {
	upgrader := websocket.Upgrader{
		CheckOrigin: h.checkOrigin,
	}
	return upgrader.Upgrade(c.Writer, c.Request, nil)
}

func (h *PosMirrorHandler) checkOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	for _, allowedOrigin := range h.allowedOrigins {
		if origin == allowedOrigin {
			return true
		}
	}
	if !h.cfg.IsProduction() {
		return strings.HasPrefix(origin, "http://localhost:") ||
			strings.HasPrefix(origin, "http://127.0.0.1:") ||
			strings.HasPrefix(origin, "https://localhost:") ||
			strings.HasPrefix(origin, "https://127.0.0.1:")
	}
	return false
}

func parseOriginList(raw string) []string {
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	origins := make([]string, 0, len(parts))
	for _, part := range parts {
		origin := strings.TrimSpace(part)
		if origin != "" {
			origins = append(origins, origin)
		}
	}
	return origins
}

// runBroadcaster registers a Van Staff connection and forwards its state updates.
func (h *PosMirrorHandler) runBroadcaster(conn *websocket.Conn, user *repository.User, branchID, posID string) {
	posKey := posMirrorKey(branchID, posID)
	b := &broadcaster{
		conn:     conn,
		userID:   user.ID,
		userName: user.Name,
		branchID: branchID,
		posID:    posID,
		posKey:   posKey,
	}

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
		if posKey != ":" {
			h.hub.posStateCache[posKey] = enriched
		}
		h.hub.mu.Unlock()

		h.hub.forwardToWatchers(user.ID, enriched)
		h.hub.forwardToCustomerDisplays(posKey, enriched)
	}
}

func (h *PosMirrorHandler) runCustomerDisplay(conn *websocket.Conn, posKey string) {
	connID := posKey + "-" + time.Now().Format("150405.000")
	display := &customerDisplay{conn: conn, connID: connID, posKey: posKey}

	h.hub.mu.Lock()
	h.hub.customerDisplays[connID] = display
	cached := h.hub.posStateCache[posKey]
	h.hub.mu.Unlock()

	if cached != nil {
		_ = conn.WriteMessage(websocket.TextMessage, cached)
	}

	defer func() {
		h.hub.mu.Lock()
		delete(h.hub.customerDisplays, connID)
		h.hub.mu.Unlock()
		_ = conn.Close()
	}()

	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			break
		}
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
