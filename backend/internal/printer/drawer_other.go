//go:build !windows

package printer

type DrawerKickResult struct {
	Target  string
	Method  string
	BinPath string
	Bytes   int
	Output  string
}

func KickCashDrawer(target string, command []byte) (DrawerKickResult, error) {
	data := BuildDrawerKick(command)
	return DrawerKickResult{Target: target, Method: "unsupported", Bytes: len(data)}, PrintRaw(target, data)
}
