#!/usr/bin/env bash
set -e -o pipefail

case "${1:-install}" in
    install)
        sdk env install
        # Reload candidate paths after the first installation
        exec bash "$0" cached
        ;;
    cached)
        sdk env
        ;;
    *)
        printf 'Usage: bash integration.sh [install|cached]\n' >&2
        exit 2
        ;;
esac

java_version=$(sed -n 's/^java=//p' .sdkmanrc)
kotlin_version=$(sed -n 's/^kotlin=//p' .sdkmanrc)
[[ "$JAVA_HOME" == "$SDKMAN_CANDIDATES_DIR/java/$java_version" ]]
[[ "$KOTLIN_HOME" == "$SDKMAN_CANDIDATES_DIR/kotlin/$kotlin_version" ]]
[[ $(command -v java) == "$JAVA_HOME/bin/java" ]]
[[ $(command -v javac) == "$JAVA_HOME/bin/javac" ]]
[[ $(command -v kotlinc) == "$KOTLIN_HOME/bin/kotlinc" ]]

java -version
javac -version
kotlinc -version

build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT

cat > "$build_dir/Hello.java" <<'JAVA'
class Hello {
    public static void main(String[] args) {
        System.out.println(System.getProperty("java.version"));
    }
}
JAVA
javac -d "$build_dir" "$build_dir/Hello.java"
[[ $(java -cp "$build_dir" Hello) == "${java_version%-*}" ]]

printf 'fun main() { println("Kotlin ready") }\n' > "$build_dir/Hello.kt"
kotlinc "$build_dir/Hello.kt" -include-runtime -d "$build_dir/hello.jar"
[[ $(java -jar "$build_dir/hello.jar") == 'Kotlin ready' ]]

printf 'Java and Kotlin installation, selection, compilation, and execution passed\n'
