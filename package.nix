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
  version = "0.159.3";

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
    "aarch64-apple-darwin" = "0k3p2ap859k5i789nvdrnqf1i0n2912lgq2alsqbb4m5ksim1pji";
    "x86_64-apple-darwin" = "1dr4xpa73zsqyx9p5hv9shianhd52ip4f6vwrnkvi29idlhaibnb";
    "x86_64-unknown-linux-musl" = "1jqv54dz7vgx6pf4qs0n35jj93l9gj9ksb708jwl5gxissra335l";
    "aarch64-unknown-linux-musl" = "19xynhp5asw716z4gi0xqvqx8rsa271qcjv87rvq0q6d7xxk0pyd";
  };

  # codex >= 0.143 spawns a separate `codex-code-mode-host` binary (found
  # next to the running executable) when "code mode" is enabled. Shipped as its
  # own release asset, so the native build must fetch and install it too.
  codeModeHostHashes = {
    "aarch64-apple-darwin" = "1ifl2pgqk8fyadiij723wdqzhgjyyqhfpjrizbqzycxpfi1jb8yi";
    "x86_64-apple-darwin" = "17yb5y34xjpn3izjadg1jf7s7nzdzsx4mj2lf59xj35wqnr8awyj";
    "x86_64-unknown-linux-musl" = "0f6lmgrhxvhd1jpxf85yii58yfplr0grrqr3a8p3h5y792cdsn0g";
    "aarch64-unknown-linux-musl" = "0vwfkf8ia9klb53d3xgq9cvfnrmz27zm5gzfpxd13p62fb24gfvw";
  };

  nodeOptionalDepHashes = {
    "darwin-arm64" = "0dqjyias435k709jlx1ldfjgnwcwq3gbmaxpp99r42px5k48r0xj";
    "darwin-x64" = "0gr6fd56r9c3bk24j6vmz9zgadsjqzaqvrn7rbsa5p87p2ywjs7y";
    "linux-x64" = "1knj0skb54xzc333qklbhcyjlly3j6iz1px2f64j8vijzry04687";
    "linux-arm64" = "0l33lk7yz5nair6s9fqv5n58v0k96rzxvwnfbsbkcbdj6w0c6i3p";
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
      sha256 = "0yfgy0pcfz0gkl5xqdy4iwbri6dyvffwi2xvgp9qs49yx62fbm9i";
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
