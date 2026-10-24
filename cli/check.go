package main

func runCheck(_ environment, out *output, _ parsedArguments) int {
	return out.fail(failure(exitUnsupported, "check-in-app",
		"clash-cli 不检查配置文件：请在 Clash App 里导入或编辑配置，App 会检查并说明问题"))
}
