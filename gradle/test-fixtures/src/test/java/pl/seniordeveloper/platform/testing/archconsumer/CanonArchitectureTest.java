package pl.seniordeveloper.platform.testing.archconsumer;

import com.tngtech.archunit.junit.AnalyzeClasses;
import pl.seniordeveloper.platform.testing.arch.AbstractArchitectureTest;

/**
 * Podklasa jak u konsumenta: inny pakiet niż klasa bazowa, bez własnych składowych. Zadanie {@code
 * test} uruchamia ją wprost przez silnik ArchUnit, a AbstractArchitectureTestTest sprawdza, że
 * dostaje wszystkie 11 odziedziczonych testów.
 */
@AnalyzeClasses(packages = "pl.seniordeveloper.platform.testing.arch.layout.canon")
class CanonArchitectureTest extends AbstractArchitectureTest {}
