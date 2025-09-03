Sim — dá pra usar **só 2 dos 3 monitores** na sessão RDP. O truque é salvar um arquivo `.rdp` e dizer quais monitores usar.

### Passo a passo (cliente clássico `mstsc.exe`)

1. **Descobrir os IDs dos monitores:**

   ```bash
   mstsc /l
   ```

   Vai abrir uma janelinha listando os monitores com IDs (0, 1, 2…). Anote os dois que você quer.

2. **Criar e salvar um .rdp:**

   * `Win + R` → `mstsc` → “Mostrar opções”.
   * Preencha o host/usuário e clique em **Salvar como…** (ex.: `C:\Users\SeuUsuario\Desktop\meu.rdp`).

3. **Editar o .rdp para escolher só dois monitores:**
   Abra o arquivo salvo e adicione (ou ajuste) estas linhas:

   ```bash
   use multimon:i:1
   selectedmonitors:s:ID_A,ID_B
   ```

   Exemplo, para usar os monitores 0 e 2:

   ```bash
   use multimon:i:1
   selectedmonitors:s:0,2
   ```

   > Dica: **não** use `span monitors:i:1` aqui; “span” trata tudo como uma tela gigante. O que você quer é **multimon** com **selectedmonitors**.

4. **Conectar usando esse .rdp:**

   ```bash
   mstsc "C:\Users\SeuUsuario\Desktop\meu.rdp"
   ```

### Observações importantes

* Os dois monitores selecionados devem estar **na mesma GPU** e idealmente com **mesma escala DPI** para evitar bordas/artefatos.
* Funciona bem em Windows Pro/Enterprise/Server no destino.
* Se quiser “forçar” via PowerShell (em vez de editar manualmente), dá pra acrescentar as linhas assim:

  ```bash
  $rdp="C:\Users\SeuUsuario\Desktop\meu.rdp"
  Add-Content $rdp "use multimon:i:1"
  Add-Content $rdp "selectedmonitors:s:0,2"
  ```

### Alternativa rápida (sem .rdp)

Se não quiser editar arquivo, uma gambiarra é **desconectar** temporariamente um monitor em **Configurações > Sistema > Tela** (seleciona o monitor > “Várias telas” > “Desconectar este vídeo”) antes de iniciar o RDP — aí o `mstsc /multimon` usará só os dois restantes. Mas o método do `.rdp` é o jeito limpo.
