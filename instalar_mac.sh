#!/bin/bash
# =============================================================================
# Instalador do V9 Lite para Mac. Cola no Terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/Hardyrx/v9lite-dist/main/instalar_mac.sh | bash
#
# Mac com chip Apple (M1 a M5), macOS 12 ou mais novo. Não pede senha de administrador nem conta de desenvolvedor da
# Apple: tudo fica na pasta do usuário. Rodar de novo = atualizar/consertar (o canal, os vídeos e a configuração ficam).
# Liberação POR CÓDIGO (igual ao Windows): mostra o código deste Mac, o suporte liga o "V9 Lite" no painel, e o servidor
# entrega a chave que abre o pacote cifrado. Sem a liberação o pacote não abre.
# =============================================================================
set -u
DIST_URL="${V9L_BASE_URL:-https://raw.githubusercontent.com/Hardyrx/v9lite-dist/main}"
LICENCA_URL="${V9_LICENCA_URL:-https://hrvrhaxllsbgiwkliuoc.supabase.co/functions/v1/licenca}"
DESTINO="${V9L_DESTINO:-$HOME/V9Lite}"
DADOS="$HOME/Library/Application Support/V9Lite"
NOME="V9 Lite"
TMP="$(mktemp -d -t v9liteinst)"
AVISOS=()
TOTAL=8

azul()  { printf '\n\033[36m[%s/%s] %s\033[0m\n' "$1" "$TOTAL" "$2"; }
ok()    { printf '      \033[32mOK -- %s\033[0m\n' "$1"; }
aviso() { printf '      \033[33mAVISO: %s\033[0m\n' "$1"; AVISOS+=("$1"); }
parar() { printf '\n      \033[31mPAROU: %s\033[0m\n\n' "$1"; rm -rf "$TMP"; exit 1; }
pergunta() { local r; read -r -p "$1" r < /dev/tty; printf '%s' "$r"; }

[ "$(uname)" = "Darwin" ] || parar "Este instalador é para Mac. No Windows use o Instalar-V9Lite.exe."
echo ""
echo "  ===================  Instalador do V9 Lite (Mac)  ==================="
MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
LIVRE_GB=$(( $(df -k "$HOME" | tail -1 | awk '{print $4}') / 1048576 ))
echo "      Este Mac: $(sysctl -n machdep.cpu.brand_string 2>/dev/null), ${MEM_GB} GB de memória, ${LIVRE_GB} GB livres."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 12 ] 2>/dev/null || parar "O V9 Lite precisa do macOS 12 (Monterey) ou mais novo."
[ "$LIVRE_GB" -ge 6 ] || parar "Pouco espaço livre (${LIVRE_GB} GB). O programa ocupa cerca de 2 GB e cada vídeo mais alguns GB."

# ---------- 1) Python (uv: sem administrador, sem Homebrew) ----------
azul 1 "Python"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
  echo "      Instalando o gerenciador de Python (uv, só para este usuário)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || parar "Não consegui instalar o Python. Confira a internet e rode de novo."
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v uv >/dev/null 2>&1 || parar "Não consegui preparar o Python."
uv python install 3.12 >/dev/null 2>&1 || parar "Não consegui baixar o Python 3.12. Confira a internet e rode de novo."
uv venv --python 3.12 --seed "$TMP/venv" >/dev/null 2>&1 || parar "Não consegui preparar a verificação de acesso."
VPY="$TMP/venv/bin/python"
UV_HTTP_TIMEOUT=60 uv pip install -q --python "$VPY" cryptography >/dev/null 2>&1 || parar "Não consegui preparar a verificação de acesso. Confira a internet."
ok "Python 3.12 pronto."

# o mesmo cálculo do código da máquina do V9 (sha256 de "v9|" + IOPlatformUUID) e o pedido "codigo" com o app "lite"
cat > "$TMP/cofre.py" <<'PY'
import base64, gzip, hashlib, io, json, os, re, socket, subprocess, sys, urllib.error, urllib.request, zipfile
def guid():
    r = subprocess.run(["/usr/sbin/ioreg", "-rd1", "-c", "IOPlatformExpertDevice"], capture_output=True, text=True)
    m = re.search(r'"IOPlatformUUID"\s*=\s*"([^"]+)"', r.stdout or "")
    return m.group(1) if m else subprocess.run(["/usr/sbin/sysctl", "-n", "kern.uuid"], capture_output=True, text=True).stdout.strip()
def maquina(): return hashlib.sha256(("v9|" + guid()).encode()).hexdigest()
def codigo(): h = maquina().upper(); return "-".join(h[i:i + 4] for i in range(0, 12, 4))
if sys.argv[1] == "codigo":
    corpo = json.dumps({"acao": "codigo", "maquina": maquina(), "app": "lite", "nome_pc": socket.gethostname()}).encode()
    req = urllib.request.Request(os.environ["LICENCA_URL"], data=corpo, headers={"content-type": "application/json"}, method="POST")
    out = {"codigo": codigo(), "estado": "sem_rede"}
    try:
        try:
            with urllib.request.urlopen(req, timeout=20) as r: j = json.loads(r.read())
        except urllib.error.HTTPError as e: j = json.loads(e.read())
        if j.get("ok") and j.get("chave_dados"): out.update(estado="liberado", chave=j["chave_dados"])
        elif j.get("ok"): out["estado"] = "sem_chave"
        elif j.get("motivo") == "aguardando_liberacao": out["estado"] = "aguardando"
        elif j.get("motivo") in ("dispositivo_bloqueado", "proibido", "vencida"): out["estado"] = "negado"
        else: out["estado"] = "servidor_antigo"
    except Exception: pass
    print(json.dumps(out))
elif sys.argv[1] == "abrir":                       # abrir <pacote> <destino>   (chave pela entrada padrão)
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    chave = sys.stdin.readline().strip(); blob = open(sys.argv[2], "rb").read()
    if blob[:4] != b"V9E1": sys.exit(3)
    try: dados = gzip.decompress(AESGCM(base64.b64decode(chave)).decrypt(blob[4:16], blob[16:], None))
    except Exception: sys.exit(4)
    dest = os.path.abspath(sys.argv[3]); z = zipfile.ZipFile(io.BytesIO(dados))
    nomes = z.namelist()
    if any(not os.path.abspath(os.path.join(dest, n)).startswith(dest + os.sep) for n in nomes): sys.exit(5)
    for n in nomes:                                # numa atualização, o que é do aluno (canal, vídeos, fila) fica como está
        if n.startswith(("config/", "videos/", "fila/", "biblioteca/")) and os.path.exists(os.path.join(dest, n)): continue
        z.extract(n, dest)
PY

# ---------- 2) liberação por código ----------
azul 2 "Liberação deste Mac"
campo() { printf '%s' "$J" | "$VPY" -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1" 2>/dev/null; }
CHAVE=""; AVISOU=0
while :; do
  J="$(LICENCA_URL="$LICENCA_URL" "$VPY" "$TMP/cofre.py" codigo 2>/dev/null | tail -1)"
  ESTADO="$(campo estado)"; CODIGO="$(campo codigo)"
  case "$ESTADO" in
    liberado) CHAVE="$(campo chave | tr -d '[:space:]')"; ok "este Mac está liberado (código $CODIGO)."; break ;;
    negado) parar "Este Mac (código $CODIGO) não tem acesso ao V9 Lite. Fale com o suporte." ;;
    sem_chave) parar "Este Mac (código $CODIGO) está liberado, mas sem direito a instalar. Fale com o suporte." ;;
    sem_rede) echo "      Não consegui falar com o servidor de licenças. Confira a internet (tento de novo em 20 s)." ;;
    servidor_antigo) parar "O servidor ainda não está pronto para o V9 Lite. Fale com o suporte." ;;
  esac
  if [ "$AVISOU" = 0 ] && [ "$ESTADO" = "aguardando" ]; then
    AVISOU=1
    echo ""
    echo "      Código deste Mac:  $CODIGO"
    echo "      Mande este código para o suporte do V9 e espere. Confiro a cada 20 segundos se já foi liberado."
  fi
  sleep "${V9L_CODIGO_INTERVALO:-20}"
done

# ---------- 3) programa ----------
azul 3 "Baixando o V9 Lite para $DESTINO"
curl -fsSL "$DIST_URL/latest.json" -o "$TMP/latest.json" || parar "Não consegui ver a versão atual. Confira a internet."
VERSAO="$("$VPY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["versao"])' "$TMP/latest.json")"
ARQ="$("$VPY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("arquivo") or "pacote.v9l")' "$TMP/latest.json")"
SHA="$("$VPY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"].lower())' "$TMP/latest.json")"
curl -fsSL "$DIST_URL/$ARQ" -o "$TMP/$ARQ" || parar "Não consegui baixar o programa. Confira a internet."
[ "$(shasum -a 256 "$TMP/$ARQ" | cut -d' ' -f1)" = "$SHA" ] || parar "O arquivo baixado não confere. Espere uns minutos e rode de novo."
if [ -d "$DESTINO" ] && [ ! -f "$DESTINO/motor/canal.py" ] && [ -n "$(ls -A "$DESTINO" 2>/dev/null)" ]; then
  parar "A pasta $DESTINO já existe e não é do V9 Lite. Renomeie essa pasta e rode de novo."
fi
mkdir -p "$DESTINO"
printf '%s\n' "$CHAVE" | "$VPY" "$TMP/cofre.py" abrir "$TMP/$ARQ" "$DESTINO"
case $? in 0) ;; 4) parar "A chave não abriu o pacote: fale com o suporte." ;; *) parar "Não consegui abrir o pacote do programa." ;; esac
CHAVE=""
printf '%s\n' "$VERSAO" > "$DESTINO/VERSAO"
chmod +x "$DESTINO"/*.command "$DESTINO/canal.sh" 2>/dev/null
ok "programa instalado (versão $VERSAO)."

# ---------- 4) ffmpeg e Node (sem Homebrew, dentro da pasta do programa) ----------
azul 4 "ffmpeg e Node"
cd "$DESTINO" || parar "Não consegui entrar na pasta do programa."
PLAT="$(uname -m)"; [ "$PLAT" = "arm64" ] || PLAT="amd64"
if [ ! -x "ffmpeg/bin/ffmpeg" ] || [ ! -x "ffmpeg/bin/ffprobe" ]; then
  mkdir -p ffmpeg/bin
  for prog in ffmpeg ffprobe; do
    curl -fsSL "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$PLAT/release/$prog.zip" -o "$TMP/$prog.zip" \
      && ditto -x -k "$TMP/$prog.zip" ffmpeg/bin && chmod +x "ffmpeg/bin/$prog" && xattr -d com.apple.quarantine "ffmpeg/bin/$prog" 2>/dev/null
  done
fi
ffmpeg/bin/ffmpeg -hide_banner -version >/dev/null 2>&1 && ok "ffmpeg pronto." || parar "Não consegui baixar o ffmpeg. Confira a internet e rode de novo."
if [ ! -x "node/bin/node" ]; then
  if [ "$(uname -m)" = "arm64" ]; then NODE_ARQ="node-v24.15.0-darwin-arm64"; NODE_SHA="372331b969779ab5d15b949884fc6eaf88d5afe87bde8ba881d6400b9100ffc4"
  else NODE_ARQ="node-v24.15.0-darwin-x64"; NODE_SHA="ffd5ee293467927f3ee731a553eb88fd1f48cf74eebc2d74a6babe4af228673b"; fi
  curl -fsSL "https://nodejs.org/dist/v24.15.0/$NODE_ARQ.tar.gz" -o "$TMP/node.tar.gz" || parar "Não consegui baixar o Node. Confira a internet."
  [ "$(shasum -a 256 "$TMP/node.tar.gz" | cut -d' ' -f1)" = "$NODE_SHA" ] || parar "O Node baixado não confere."
  tar -xzf "$TMP/node.tar.gz" -C "$TMP" && rm -rf node && mv "$TMP/$NODE_ARQ" node
fi
export PATH="$DESTINO/ffmpeg/bin:$DESTINO/node/bin:$PATH"
node -v >/dev/null 2>&1 && ok "Node pronto." || parar "O Node não ficou pronto."

# ---------- 5) bibliotecas do motor e navegador das cenas ----------
azul 5 "Bibliotecas do motor e navegador das cenas (a parte mais demorada)"
mkdir -p "$DADOS"
[ -x "$DADOS/venv/bin/python" ] || uv venv --python 3.12 --seed "$DADOS/venv" >/dev/null 2>&1 || parar "Não consegui criar o ambiente do programa."
UV_HTTP_TIMEOUT=120 uv pip install -q --python "$DADOS/venv/bin/python" -r requirements.txt || parar "A instalação das bibliotecas falhou. Confira a internet e rode de novo."
cp requirements.txt "$DADOS/venv/instalado_requirements.txt"
( cd motor && npm install --no-audit --no-fund --loglevel=error >/dev/null 2>&1 && npx playwright install chromium >/dev/null 2>&1 ) \
  || parar "Não consegui instalar o navegador das cenas. Confira a internet e rode de novo."
ok "motor pronto."
"$DADOS/venv/bin/python" motor/vozes.py --instalar >/dev/null 2>&1 && ok "voz local (reserva, sem internet) pronta." || aviso "A voz local não ficou pronta agora; a voz online funciona normalmente."

# ---------- 6) Claude Code ----------
azul 6 "Claude Code (quem conversa com você e escreve os roteiros)"
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
CLAUDE="$HOME/.local/bin/claude"
if [ ! -x "$CLAUDE" ]; then
  echo "      Instalando o Claude Code oficial (claude.ai/install.sh)..."
  curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1
fi
if [ ! -x "$CLAUDE" ]; then aviso "Não consegui instalar o Claude Code. Abra o \"V9 Lite\" depois: ele tenta de novo."
elif "$CLAUDE" auth status >/dev/null 2>&1; then ok "Claude Code pronto e com login."
else
  echo "      Agora o LOGIN do Claude: vai abrir o navegador. Entre com a conta que tem a assinatura Pro ou Max."
  pergunta '      Aperte Enter para abrir o login ' >/dev/null
  "$CLAUDE" auth login --claudeai < /dev/tty
  "$CLAUDE" auth status >/dev/null 2>&1 && ok "login do Claude feito." || aviso "O login do Claude não foi concluído: abra o \"V9 Lite\" e digite /login."
fi

# ---------- 7) apps no Launchpad ----------
azul 7 "Criando os apps \"$NOME Estúdio\" e \"$NOME Terminal\""
mkdir -p "$HOME/Applications"
# 18/10: o Painel saiu e o app da conversa no Terminal ganhou nome claro (antes eram 3 "V9 Lite" parecidos no Launchpad)
rm -rf "$HOME/Applications/V9 Lite Painel.app" "$HOME/Applications/V9 Lite.app"
for par in "V9 Lite Estúdio|ESTUDIO.command" "V9 Lite Terminal|ABRIR.command"; do
  nome="${par%%|*}"; alvo="${par##*|}"; app="$HOME/Applications/$nome.app"
  rm -rf "$app"
  if [ "$alvo" = "ESTUDIO.command" ]; then                 # o Estúdio é APP: abre a janela própria, sem Terminal
    osacompile -o "$app" -e "do shell script \"'$DESTINO/canal.sh' estudio > '$DADOS/estudio.log' 2>&1 &\"" || aviso "Não consegui criar o app $nome."
  else
    osacompile -o "$app" -e "do shell script \"open -a Terminal '$DESTINO/$alvo'\"" || aviso "Não consegui criar o app $nome."
  fi
  [ -f "$DESTINO/icones/v9lite.icns" ] && cp "$DESTINO/icones/v9lite.icns" "$app/Contents/Resources/applet.icns"   # a cabeça do robozinho V9
  touch "$app"
done
ok "apps em Aplicativos do usuário (~/Applications): aparecem no Launchpad e no Spotlight."

# ---------- 8) resumo ----------
azul 8 "Resumo"
rm -rf "$TMP"
if [ ${#AVISOS[@]} -eq 0 ]; then ok "tudo certo, nenhuma pendência."; else echo "      Instalado, com pendências:"; for a in "${AVISOS[@]}"; do echo "       - $a"; done; fi
echo ""
echo "  Para usar: abra \"V9 Lite Estúdio\" pelo Launchpad (criar vídeo por escolhas, sem conversa)."
echo "  Também: \"V9 Lite\" (a conversa com a IA) e \"V9 Lite Painel\" (o escritório e a aprovação)."
echo "  Para atualizar: rode este mesmo comando de novo (o canal, os vídeos e a configuração ficam)."
echo ""
R="$(pergunta '  Abrir o V9 Lite agora? (S/N): ')"
if [ "$R" = "s" ] || [ "$R" = "S" ]; then open "$HOME/Applications/V9 Lite Estúdio.app"; fi
