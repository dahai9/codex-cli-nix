{ lib
, stdenv
, fetchurl
, nodejs_22
, cacert
, makeWrapper
, installShellFiles
, installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform
, gnutar
, gzip
, openssl
, libcap
, libz
, bubblewrap
, ripgrep
, runtime ? "native"
, nativeBinName ? "codex"
, nodeBinName ? "codex-node"
}:

let
  version = "0.162.1";

  platformMap = {
    "aarch64-darwin" = "aarch64-apple-darwin";
    "x86_64-darwin" = "x86_64-apple-darwin";
    "x86_64-linux" = "x86_64-unknown-linux-musl";
    "aarch64-linux" = "aarch64-unknown-linux-musl";
  };

  nodePlatformMap = {
    "aarch64-darwin" = "darwin-arm64";
    "x86_64-darwin" = "darwin-x64";
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
  };

  platform = platformMap.${stdenv.hostPlatform.system} or null;
  nodePlatform = nodePlatformMap.${stdenv.hostPlatform.system} or null;

  nativeHashes = {
    "aarch64-apple-darwin" = "1znigwbx3mcbvgmr1xsl53h326s0mahl0kqa9jj006c7vpya14xj";
    "x86_64-apple-darwin" = "088vqbisrcrawqkkhjk6ks0gfglwrda6ar80glzz6f96yvc3k3nn";
    "x86_64-unknown-linux-musl" = "0msh2bxf13skf9dikmj2w015hb6s5ynz5ksy9ha3x3w93gc6iwl6";
    "aarch64-unknown-linux-musl" = "1h804q5wdkmzz28pkbah5iw6qscy6x4w31dx1x2b2hqikxqs4g5z";
  };

  # codex >= 0.143 spawns a separate `codex-code-mode-host` binary (found
  # next to the running executable) when "code mode" is enabled. Shipped as its
  # own release asset, so the native build must fetch and install it too.
  codeModeHostHashes = {
    "aarch64-apple-darwin" = "09rp5fb83ibq4pa3drhkgv7qbd1cxydz2sqv8dp93g5djhl4lihz";
    "x86_64-apple-darwin" = "0dqx265fizag8xap34dhfp7ps3lrpjchqvgkm8wq5cc4d25aylnd";
    "x86_64-unknown-linux-musl" = "1nls7424yvs6lhlnk958153q7wjjnc51hpv9i66m1z618pm3k0j5";
    "aarch64-unknown-linux-musl" = "16hy33lxsgsgppam30wbj0fj5gr5vwz0izsdcy0d5b7qcy9wx58k";
  };

  nodeOptionalDepHashes = {
    "darwin-arm64" = "1bd97f98hrd5pyisq6zzk9piych2hnnq5d2j07f7l8q5g81700zy";
    "darwin-x64" = "1v7mf0a6zqsqf8hyi19cz78kvl6bhrvs9hsvndp0iwcrsdlkvxg4";
    "linux-x64" = "17y0ym7y0mjby5qhxni8556cicwbx0wnw4k40vkywr5lg0b725vl";
    "linux-arm64" = "0jxd1jkai7hrw9zgq8z2jqppy0agyymwwnp5887davi91hfhamd3";
  };

  nativeBinaryUrl = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${platform}.tar.gz";

  nativeBinary = if runtime == "native" && platform != null then
    fetchurl {
      url = nativeBinaryUrl;
      sha256 = nativeHashes.${platform};
    }
  else null;

  codeModeHost = if runtime == "native" && platform != null then
    fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-code-mode-host-${platform}.tar.gz";
      sha256 = codeModeHostHashes.${platform};
    }
  else null;

  npmTarball = if runtime == "node" then
    fetchurl {
      url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz";
      sha256 = "1sk55ga8bzdnd0054krjig5v6w3pvpc88d4hkkvf90sqlqrjwjqb";
    }
  else null;

  nodeOptionalDep = if runtime == "node" && nodePlatform != null then
    fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-npm-${nodePlatform}-${version}.tgz";
      sha256 = nodeOptionalDepHashes.${nodePlatform};
    }
  else null;

  runtimeConfig = {
    native = {
      nativeBuildInputs = [ gnutar gzip makeWrapper ];
      buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ openssl libcap libz ];
      description = "OpenAI Codex CLI (Native Binary) - AI coding assistant in your terminal";
      binName = nativeBinName;
    };
    node = {
      nativeBuildInputs = [ nodejs_22 cacert makeWrapper ];
      buildInputs = [];
      description = "OpenAI Codex CLI (Node.js) - AI coding assistant in your terminal";
      binName = nodeBinName;
    };
  };

  selected = runtimeConfig.${runtime};
  linuxRuntimePath = lib.makeBinPath (lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap ]);
  generateShellCompletions =
    installShellCompletions
    && runtime == "native"
    && selected.binName == "codex";
in
assert runtime == "native" -> platform != null ||
  throw "Native runtime not supported on ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-darwin, x86_64-linux, aarch64-linux";

stdenv.mkDerivation rec {
  pname = if runtime == "native" then "codex" else "codex-${runtime}";
  inherit version;

  dontUnpack = true;

  dontPatchELF = runtime == "native";
  dontStrip = runtime == "native";

  nativeBuildInputs = selected.nativeBuildInputs
    ++ lib.optionals generateShellCompletions [ installShellFiles ];
  buildInputs = selected.buildInputs;

  buildPhase = if runtime == "native" then ''
    runHook preBuild
    mkdir -p build
    tar -xzf ${nativeBinary} -C build
    mv build/codex-${platform} build/codex
    chmod u+w,+x build/codex

    tar -xzf ${codeModeHost} -C build
    mv build/codex-code-mode-host-${platform} build/codex-code-mode-host
    chmod u+w,+x build/codex-code-mode-host

    runHook postBuild
  '' else ''
    runHook preBuild
    export HOME=$TMPDIR
    mkdir -p $HOME/.npm

    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export NODE_EXTRA_CA_CERTS=$SSL_CERT_FILE

    mkdir -p $out/lib/node_modules/@openai
    tar -xzf ${npmTarball} -C $out/lib/node_modules/@openai
    mv $out/lib/node_modules/@openai/package $out/lib/node_modules/@openai/codex

    ${lib.optionalString (nodeOptionalDep != null) ''
    tar -xzf ${nodeOptionalDep} -C $out/lib/node_modules/@openai
    mv $out/lib/node_modules/@openai/package $out/lib/node_modules/@openai/codex-${nodePlatform}
    ''}

    runHook postBuild
  '';

  installPhase = if runtime == "native" then ''
    runHook preInstall
    # Codex 0.157+ discovers daemon update/install support from the complete
    # package layout next to the running executable.  Keep the native binary
    # in that layout instead of hiding it behind a wrapper in libexec.
    mkdir -p $out/bin $out/codex-path $out/codex-resources
    cp build/codex "$out/bin/${selected.binName}"
    chmod +x "$out/bin/${selected.binName}"
    cp build/codex-code-mode-host "$out/bin/codex-code-mode-host"
    chmod +x "$out/bin/codex-code-mode-host"
    cp ${ripgrep}/bin/rg "$out/codex-path/rg"
    chmod +x "$out/codex-path/rg"
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      cp ${bubblewrap}/bin/bwrap "$out/codex-resources/bwrap"
      chmod +x "$out/codex-resources/bwrap"
    ''}
    cat > "$out/codex-package.json" <<EOF
{
  "layoutVersion": 1,
  "version": "${version}",
  "target": "${platform}",
  "variant": "codex",
  "entrypoint": "bin/${selected.binName}",
  "resourcesDir": "codex-resources",
  "pathDir": "codex-path"
}
EOF
    runHook postInstall
  '' else ''
    runHook preInstall
    mkdir -p $out/bin

    makeWrapper ${nodejs_22}/bin/node "$out/bin/${selected.binName}" \
      --add-flags --no-warnings \
      --add-flags "$out/lib/node_modules/@openai/codex/bin/codex.js" \
      --set NODE_PATH "$out/lib/node_modules" \
      --run 'export CODEX_EXECUTABLE_PATH="$HOME/.local/bin/${selected.binName}"' \
      --set DISABLE_AUTOUPDATER 1 \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''--prefix PATH : "${linuxRuntimePath}"''}
    runHook postInstall
  '';

  postInstall = lib.optionalString generateShellCompletions ''
    installShellCompletion --cmd codex \
      --bash <("$out/bin/${selected.binName}" completion bash) \
      --fish <("$out/bin/${selected.binName}" completion fish) \
      --zsh <("$out/bin/${selected.binName}" completion zsh)
  '';

  meta = with lib; {
    description = selected.description;
    homepage = "https://github.com/openai/codex";
    license = licenses.asl20;
    platforms = if runtime == "native" then
      [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ]
    else
      platforms.all;
    mainProgram = selected.binName;
  };
}
