package pl.seniordeveloper.gradle

import org.gradle.api.services.BuildService
import org.gradle.api.services.BuildServiceParameters

/**
 * Współdzielony limit testów w trybie AI_AGENT: `maxParallelUsages = 1`, więc w jednym buildzie biegnie naraz
 * jeden task testowy. Uzasadnienie i pomiar: docs/adr/0010-agent-resource-profile.md.
 */
abstract class AgentTestBudget : BuildService<BuildServiceParameters.None>
