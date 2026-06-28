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
	if err := PrintRaw(target, data); err != nil {
		return DrawerKickResult{Target: target, Method: "dev_stub", Bytes: len(data)}, err
	}
	return DrawerKickResult{Target: target, Method: "dev_stub", Bytes: len(data)}, nil
}
