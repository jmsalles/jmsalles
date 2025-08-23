Se você quer **colar imagens direto no VS Code** (em Markdown, wiki ou README por exemplo), existem extensões que fazem isso automaticamente. Algumas bem usadas:

### 🔌 Extensões recomendadas

1. **Paste Image** (by mushan)

   - Atalho padrão: `Ctrl+Alt+V` (Windows/Linux) ou `Cmd+Alt+V` (Mac).
   - Quando você copia uma imagem da área de transferência e cola no VS Code, ele salva a imagem em uma pasta (ex: `images/`) e insere o link no `.md`:

     ```markdown
     ![descricao](images/2025-08-21-01-30-00.png)
     ```

   - Permite configurar o caminho padrão e o formato do nome do arquivo.

2. **Markdown Paste**

   - Similar ao anterior, mas otimizado para quem trabalha muito com Markdown.
   - Reconhece automaticamente se você está em um arquivo `.md`.

3. **Markdown Image**

   - Além de colar imagens da área de transferência, suporta drag-and-drop de arquivos direto no Markdown.

---

### ⚙️ Como instalar

1. No VS Code, aperte `Ctrl+Shift+X` para abrir as extensões.
2. Procure por **Paste Image**.
3. Clique em **Install**.

---

### 🔧 Configuração básica do Paste Image

No `settings.json`, você pode ajustar, por exemplo:

```json
"pasteImage.path": "${currentFileDir}/images",
"pasteImage.basePath": "${projectRoot}",
"pasteImage.prefix": "img-"
```

Isso vai salvar todas as imagens na pasta `images` ao lado do `.md` e prefixar os nomes com `img-`.

---

Quer que eu já te monte um exemplo de configuração pronta para que todas as imagens coladas em Markdown fiquem numa pasta `docs/images/` no seu projeto?
