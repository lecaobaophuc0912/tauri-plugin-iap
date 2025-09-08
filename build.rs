#[cfg(all(feature = "unstable", target_os = "macos"))]
use std::{path::PathBuf, process::Command};

const COMMANDS: &[&str] = &[
    "initialize",
    "get_products",
    "purchase",
    "restore_purchases",
    "get_purchase_history",
    "acknowledge_purchase",
    "get_product_status",
];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .ios_path("ios")
        .build();

    #[cfg(all(feature = "unstable", target_os = "macos"))]
    {
        // Only run macOS-specific build steps when building for macOS
        if std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() == "macos" {
            let bridges = vec!["src/macos.rs"];
            for path in &bridges {
                println!("cargo:rerun-if-changed={path}");
            }

            swift_bridge_build::parse_bridges(bridges)
                .write_all_concatenated(swift_bridge_out_dir(), env!("CARGO_PKG_NAME"));

            compile_swift();

            println!("cargo:rustc-link-lib=static=tauri-plugin-iap");
            println!(
                "cargo:rustc-link-search={}",
                swift_library_static_lib_dir().to_str().unwrap()
            );

            // Without this we will get warnings about not being able to find dynamic libraries, and then
            // we won't be able to compile since the Swift static libraries depend on them:
            // For example:
            // ld: warning: Could not find or use auto-linked library 'swiftCompatibility51'
            // ld: warning: Could not find or use auto-linked library 'swiftCompatibility50'
            // ld: warning: Could not find or use auto-linked library 'swiftCompatibilityDynamicReplacements'
            // ld: warning: Could not find or use auto-linked library 'swiftCompatibilityConcurrency'
            let xcode_path = if let Ok(output) = std::process::Command::new("xcode-select")
                .arg("--print-path")
                .output()
            {
                String::from_utf8(output.stdout.as_slice().into())
                    .unwrap()
                    .trim()
                    .to_string()
            } else {
                "/Applications/Xcode.app/Contents/Developer".to_string()
            };
            println!(
            "cargo:rustc-link-search={}/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/",
            &xcode_path
        );
            println!("cargo:rustc-link-search=/usr/lib/swift");

            let p = "/Library/Developer/CommandLineTools/usr/lib/swift-5.5/macosx";
            println!("cargo:rustc-link-search=native={p}");
            println!("cargo:rustc-link-arg=-Wl,-rpath,{p}");

            println!(
                "cargo:rustc-link-search=/Library/Developer/CommandLineTools/usr/lib/swift-5.5/macosx"
            );
        }
    }
}

#[cfg(all(feature = "unstable", target_os = "macos"))]
fn compile_swift() {
    let swift_package_dir = manifest_dir().join("macos");

    let mut cmd = Command::new("swift");

    cmd.current_dir(swift_package_dir).arg("build").args([
        "-Xswiftc",
        "-import-objc-header",
        "-Xswiftc",
        swift_source_dir()
            .join("bridging-header.h")
            .to_str()
            .unwrap(),
    ]);

    if is_release_build() {
        cmd.args(["-c", "release"]);
    }

    let exit_status = cmd.spawn().unwrap().wait_with_output().unwrap();

    if !exit_status.status.success() {
        panic!(
            r#"
Stderr: {}
Stdout: {}
"#,
            String::from_utf8(exit_status.stderr).unwrap(),
            String::from_utf8(exit_status.stdout).unwrap(),
        )
    }
}

#[cfg(all(feature = "unstable", target_os = "macos"))]
fn swift_bridge_out_dir() -> PathBuf {
    generated_code_dir()
}

#[cfg(all(feature = "unstable", target_os = "macos"))]
fn manifest_dir() -> PathBuf {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    PathBuf::from(manifest_dir)
}

#[cfg(all(feature = "unstable", target_os = "macos"))]
fn is_release_build() -> bool {
    std::env::var("PROFILE").unwrap() == "release"
}

#[cfg(all(feature = "unstable", target_os = "macos"))]
fn swift_source_dir() -> PathBuf {
    manifest_dir().join("macos/Sources")
}

#[cfg(all(feature = "unstable", target_os = "macos"))]
fn generated_code_dir() -> PathBuf {
    swift_source_dir().join("generated")
}

#[cfg(all(feature = "unstable", target_os = "macos"))]
fn swift_library_static_lib_dir() -> PathBuf {
    let debug_or_release = if is_release_build() {
        "release"
    } else {
        "debug"
    };

    manifest_dir().join(format!("macos/.build/{debug_or_release}"))
}
