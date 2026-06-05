// build-logic = osobny build Gradle publikujący convention plugins (precompiled script plugins)
// jako artefakt Maven. Konsumowany przez 3 repo (Attestate / SkillSprintPlus / BookOfStyling)
// przez `pluginManagement { repositories { maven(GitHub Packages) } }`.
rootProject.name = "build-logic"
