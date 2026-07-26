/**
 * Precompiled [seniordev.settings-conventions.settings.gradle.kts][Seniordev_settings_conventions_settings_gradle] script plugin.
 *
 * @see Seniordev_settings_conventions_settings_gradle
 */
public
class Seniordev_settingsConventionsPlugin : org.gradle.api.Plugin<org.gradle.api.initialization.Settings> {
    override fun apply(target: org.gradle.api.initialization.Settings) {
        try {
            Class
                .forName("Seniordev_settings_conventions_settings_gradle")
                .getDeclaredConstructor(org.gradle.api.initialization.Settings::class.java, org.gradle.api.initialization.Settings::class.java)
                .newInstance(target, target)
        } catch (e: java.lang.reflect.InvocationTargetException) {
            throw e.targetException
        }
    }
}
