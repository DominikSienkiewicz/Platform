/**
 * Precompiled [seniordev.spring-modulith-conventions.gradle.kts][Seniordev_spring_modulith_conventions_gradle] script plugin.
 *
 * @see Seniordev_spring_modulith_conventions_gradle
 */
public
class Seniordev_springModulithConventionsPlugin : org.gradle.api.Plugin<org.gradle.api.Project> {
    override fun apply(target: org.gradle.api.Project) {
        try {
            Class
                .forName("Seniordev_spring_modulith_conventions_gradle")
                .getDeclaredConstructor(org.gradle.api.Project::class.java, org.gradle.api.Project::class.java)
                .newInstance(target, target)
        } catch (e: java.lang.reflect.InvocationTargetException) {
            throw e.targetException
        }
    }
}
