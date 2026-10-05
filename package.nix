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
  version = "0.160.1";

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
    "aarch64-apple-darwin" = "1l4496a5334mv0fh0xbil09ks0y561gkinnpfkxmmjfr96qg42k7";
    "x86_64-apple-darwin" = "1drdy1xblzr2lak04cs61skmlk2ixn26jq7i8lflnhn4jgdqv4wd";
    "x86_64-unknown-linux-musl" = "0gx3pf28r26k16dypxrrbvj63ak3vcpka2klgxz8zlcjwldmh9lj";
    "aarch64-unknown-linux-musl" = "1xz1yyc5bp3kvrs41851qm92zc1wdwak3am33ps5ni22422wakgm";
  };

  # codex >= 0.143 spawns a separate `codex-code-mode-host` binary (found
  # next to the running executable) when "code mode" is enabled. Shipped as its
  # own release asset, so the native build must fetch and install it too.
  codeModeHostHashes = {
    "aarch64-apple-darwin" = "1ny703l27f6vhh019z4i8lfsnccgp8bpqg0cbcqgl84jkpv2sl3f";
    "x86_64-apple-darwin" = "0ix1pc4lk6kfrlf4q49fb72n3286dyjqfcjy0sfanv1c3izfc2nd";
    "x86_64-unknown-linux-musl" = "1hp3w0jvn4mmgm8hdkzabnp52k3swvhp8naqnr9wfnjljxyj0sca";
    "aarch64-unknown-linux-musl" = "0hcprxyvkjfn5qahwd8351iiifqfkwbh19haazis5zcyd3k2gq75";
  };

  nodeOptionalDepHashes = {
    "darwin-arm64" = "15pjls0084ns3388m521waipgv6vhcbn33zq43dprrrgdjp1q4lk";
    "darwin-x64" = "18xm9h8n15kbxkna6xmprsyh2ly7k94m7s73bgp804jjsryflicv";
    "linux-x64" = "0n7pjhmg6i3x4n6mbggkbsqbh1ch0jjiamdxqk59rw9s7l9vv7nw";
    "linux-arm64" = "1v9vfxamynkyl9ndpw2d0m46znykqrq54snqixs06594pgfkdrg1";
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
      sha256 = "1h70nicmdk483bfz1ispjvl26j95dqy0fw1jigbssq9gm37m8i6q";
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
