import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const sourcePath = path.join(
  scriptDirectory,
  "kaggle_yolo11_plant_classification.py",
);
const notebookPath = path.join(
  scriptDirectory,
  "kaggle_yolo11_plant_classification.ipynb",
);

const source = fs.readFileSync(sourcePath, "utf8").replace(/\r\n/g, "\n");
const lines = source.split("\n");
const cells = [];
let currentType = null;
let currentLines = [];

function flushCell() {
  if (currentType === null) {
    return;
  }

  let cellSource = currentLines;
  if (currentType === "markdown") {
    cellSource = currentLines.map((line) => line.replace(/^# ?/, ""));
  }

  const sourceLines = cellSource.map((line, index) => {
    const isLast = index === cellSource.length - 1;
    return isLast ? line : `${line}\n`;
  });

  if (currentType === "markdown") {
    cells.push({
      cell_type: "markdown",
      metadata: {},
      source: sourceLines,
    });
  } else {
    cells.push({
      cell_type: "code",
      execution_count: null,
      metadata: {},
      outputs: [],
      source: sourceLines,
    });
  }
}

for (const line of lines) {
  if (line === "# %% [markdown]") {
    flushCell();
    currentType = "markdown";
    currentLines = [];
  } else if (line === "# %%") {
    flushCell();
    currentType = "code";
    currentLines = [];
  } else {
    currentLines.push(line);
  }
}
flushCell();

const notebook = {
  cells,
  metadata: {
    kernelspec: {
      display_name: "Python 3",
      language: "python",
      name: "python3",
    },
    language_info: {
      name: "python",
      version: "3",
    },
  },
  nbformat: 4,
  nbformat_minor: 5,
};

fs.writeFileSync(notebookPath, `${JSON.stringify(notebook, null, 2)}\n`);
console.log(`Notebook gerado: ${notebookPath}`);

