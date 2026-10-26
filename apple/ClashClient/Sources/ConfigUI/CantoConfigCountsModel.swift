import Combine
import Foundation

/// 配置页的分组计数。
///
/// 计数只做展示，不参与任何业务判断；所有文件与 YAML 读取都离开主线程，
/// 读不到时保持 `nil`，由视图省略副标题，而不是显示一个假的 0。
@MainActor
final class CantoConfigCountsModel: ObservableObject {
    @Published private(set) var ruleCount: Int?
    @Published private(set) var moduleCount: Int?
    @Published private(set) var rewriteCount: Int?
    @Published private(set) var scriptCount: Int?
    @Published private(set) var mitmCount: Int?

    private var generation: UInt64 = 0
    private var countedProfileID: String?

    func refresh(
        profile: Profile?,
        profiles: ProfilesViewModel,
        container: URL?
    ) {
        generation &+= 1
        let generation = generation

        if countedProfileID != profile?.id {
            countedProfileID = profile?.id
            ruleCount = nil
        }

        guard let profile else {
            moduleCount = nil
            rewriteCount = nil
            scriptCount = nil
            mitmCount = nil
            return
        }

        // 规则数来自当前档案的生效 YAML；大配置的解析要几秒，放在 detached 任务里。
        Task { [weak self] in
            let yaml = await profiles.loadEffectiveYAML(for: profile)
            let count = await Task.detached(priority: .utility) {
                ProfileConfigTally.make(sourceYAML: yaml)?.rules
            }.value
            guard let self, self.generation == generation else { return }
            self.ruleCount = count
        }

        // 模块、复写、脚本、MitM 都是容器级数据，与当前档案无关；
        // 逐模块读 manifest 可能很多次文件 IO，同样放到后台。
        guard let container else {
            moduleCount = nil
            rewriteCount = nil
            scriptCount = nil
            mitmCount = nil
            return
        }
        let libraryScriptCount = ScriptLibrary.load().count
        Task { [weak self] in
            let counts = await Task.detached(priority: .utility) {
                await Self.readModuleCounts(
                    container: container,
                    libraryScriptCount: libraryScriptCount
                )
            }.value
            guard let self, self.generation == generation else { return }
            self.moduleCount = counts.moduleCount
            self.rewriteCount = counts.rewriteCount
            self.scriptCount = counts.scriptCount
            self.mitmCount = counts.mitmCount
        }
    }

    private struct ModuleCounts: Sendable {
        var moduleCount: Int?
        var rewriteCount: Int?
        var scriptCount: Int?
        var mitmCount: Int?
    }

    nonisolated private static func readModuleCounts(
        container: URL,
        libraryScriptCount: Int
    ) async -> ModuleCounts {
        let store = ModuleStore.shared(container)
        guard let state = try? await store.state() else {
            return ModuleCounts(
                moduleCount: nil,
                rewriteCount: nil,
                scriptCount: nil,
                mitmCount: nil
            )
        }

        var rewrites = 0
        var scripts = libraryScriptCount
        for record in state.modules {
            guard let ir = await store.publishedModule(record.id) else { continue }
            rewrites += ir.rewriteRules.count
            scripts += ir.scripts.count + ir.appScripts.count
        }

        let mitm = await store.publishedGlobalManifest()?
            .mitmHosts.items
            .filter { !$0.entry.excluded }
            .count

        return ModuleCounts(
            moduleCount: state.modules.count,
            rewriteCount: rewrites,
            scriptCount: scripts,
            mitmCount: mitm
        )
    }
}
