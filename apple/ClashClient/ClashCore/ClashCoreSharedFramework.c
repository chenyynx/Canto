// The one object compiled into the shared-core framework. The framework's
// substance is the force-loaded gomobile archive (project.yml, ClashCore
// target); the linker still wants an object of the target's own, and this
// string is the shipping discriminant: it exists in
// Frameworks/Clash.framework/Clash and in neither the app nor the appex.
const char *const ClashCoreSharedFrameworkMarker = "clash-core-shared-framework";
