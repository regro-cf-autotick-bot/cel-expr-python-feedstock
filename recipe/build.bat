@echo on
setlocal enabledelayedexpansion

@rem On Windows we do not use the conda system libraries for abseil/protobuf
@rem (the abseil_dll setup used by the bazel systemlibs is not compatible with
@rem Windows, see the protobuf-feedstock). Instead bazel resolves abseil,
@rem protobuf and cel-cpp from the Bazel registry and links them statically.
@rem There is therefore no `bazel-toolchain`/`gen-bazel-toolchain` step here;
@rem bazel auto-detects the MSVC toolchain provided by the compiler activation.

@rem Use the official Bazel release binary (downloaded as a source into SRC_DIR)
@rem rather than the conda-forge bazel package, whose Windows build reports
@rem `no_version` and lacks the `_cc_internal.freeze` symbol required by rules_cc
@rem (see bazelbuild/bazel#29158). setup.py invokes `bazel` from PATH.
set "PATH=%SRC_DIR%;%PATH%"
echo 8.7.0>.bazelversion

@rem Point Bazel at the MSYS2 bash provided by m2-base.
set "BAZEL_SH=%BUILD_PREFIX%\Library\usr\bin\bash.exe"

@rem Use a short output base on the build drive to avoid Windows MAX_PATH
@rem issues with the deeply nested bazel output tree.
for %%d in ("%SRC_DIR%") do set "BLDDRIVE=%%~dd"
set "BAZEL_OB=%BLDDRIVE%\_b"
md "%BAZEL_OB%" 2>nul

@rem cel-cpp / abseil require C++17 while MSVC defaults to an older standard.
@rem bazel reads the workspace .bazelrc automatically, so inject the required
@rem flags there (setup.py invokes bazel itself and we cannot pass flags to it).
echo.>> .bazelrc
echo startup --output_base=%BAZEL_OB:\=/%>> .bazelrc
echo build --cxxopt=/std:c++17>> .bazelrc
echo build --host_cxxopt=/std:c++17>> .bazelrc

copy release\pyproject.toml .
if %ERRORLEVEL% neq 0 exit 1
copy release\setup.py .
if %ERRORLEVEL% neq 0 exit 1

@rem Substitute $VERSION in pyproject.toml with the package version.
sed -i "s/\$VERSION/%PKG_VERSION%/g" pyproject.toml
if %ERRORLEVEL% neq 0 exit 1

@rem Pin the hermetic Python interpreter that rules_python uses to the version
@rem we are currently building for.
sed -i "s/python_version = \"3.11\"/python_version = \"%PY_VER%\"/" MODULE.bazel
if %ERRORLEVEL% neq 0 exit 1

@rem setup.py re-applies the python version with `sed -i 's/.../.../'` through a
@rem POSIX shell. cmd.exe does not strip the single quotes, so disable that call;
@rem we already pinned the version in MODULE.bazel above.
sed -i "s/subprocess.check_call(sed_command, shell=True)/pass/" setup.py
if %ERRORLEVEL% neq 0 exit 1

@rem Remove cel_expr_python.ext.* extension modules from setup.py. These link to
@rem the same protobuf descriptors as the main module, causing an internal protobuf
@rem assertion failure (duplicate descriptors in the pool) when both are imported.
sed -i "/BazelExtension(/{N;/cel_expr_python\.ext\./{N;N;d}}" setup.py
if %ERRORLEVEL% neq 0 exit 1

del /q cel_expr_python\*_test.py 2>nul

%PYTHON% -m pip install -vvv .
if %ERRORLEVEL% neq 0 exit 1

bazel clean --expunge
bazel shutdown
