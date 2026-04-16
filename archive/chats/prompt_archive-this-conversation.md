# Prompt: Archive This Amazing Conversation

## Configuration (for the human)

Your human will replace `chat.CHANGEME` with their desired base name. This drives all output paths:

## Configuration (for the AI model)

```
BASENAME = chat.CHANGEME
```

> - Markdown file: `${BASENAME}.md`
> - Images directory: `${BASENAME}.images/`
> - Zip archive: `${BASENAME}.zip`

---

## Task

Archive this entire conversation into a markdown document with associated
images, packaged as a zip file.

You have everything you need:
- The full conversation text is in your context window.
- All uploaded images are in `/mnt/user-data/uploads/`.

---

## Markdown Format

- **Speaker labels:**
  ```
  ## User
  [message]

  ## Assistant
  [response]
  ```
- **No timestamps** on messages.
- **No `<thinking>` blocks.**
- **Do NOT** include separate code artifact files.
- **DO** include inline code in the markdown output.
- **Preserve language hints** (e.g., ` ```bash `, ` ```javascript `).

## Image Handling

- Copy all user-uploaded images from `/mnt/user-data/uploads/` into the
  `${BASENAME}.images/` directory, preserving original filenames.
- Place each image reference **before** the user message text it accompanies.
- For messages with multiple images, list them in attachment order, each on
  its own line with a blank line between.
- **Alt text** = the image filename.
- **All paths must be relative:** `${BASENAME}.images/filename.ext`
- Do NOT base64-encode images into the markdown.

## Zip Structure

```
${BASENAME}.zip
├── ${BASENAME}.md
└── ${BASENAME}.images/
    ├── image1.png
    ├── image2.png
    └── ...
```

---

## Quality Checklist (verify before delivering)

- [ ] Every image in `/mnt/user-data/uploads/` is in the images directory
- [ ] Every image in the images directory is referenced in the markdown
- [ ] Every image reference uses a relative path
- [ ] Every image reference has alt text (no empty `![]()`)
- [ ] Speaker labels are `## User` and `## Assistant` only
- [ ] No timestamps, no thinking blocks
- [ ] Code blocks retain language hints
- [ ] Zip contains both the markdown file and the images directory

---

## Processing Rules (for Claude)

- Do NOT include this archival prompt and its response in the archived output.
- If any uploaded files are NOT images (e.g., `.md`, `.zip`, `.txt`), exclude
  them from the images directory — only include actual image files
  (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`).
