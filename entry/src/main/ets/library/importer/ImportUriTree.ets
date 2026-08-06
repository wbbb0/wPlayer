/**
 * Groups picker-authorized URIs into a display tree for import range
 * selection. URI path segments are used only to build this presentation
 * tree and are never used to access the file system; the URIs themselves
 * remain opaque authorization-managed strings.
 */

export enum ImportTreeCheckState {
  NONE = 0,
  PARTIAL = 1,
  ALL = 2
}

export enum ImportTreeRowKind {
  DIR = 0,
  FILE = 1
}

export class ImportTreeFileNode {
  readonly uri: string;
  readonly name: string;
  parent?: ImportTreeDirNode;
  selected: boolean = true;

  constructor(uri: string, name: string) {
    this.uri = uri;
    this.name = name;
  }
}

export class ImportTreeDirNode {
  name: string;
  readonly pathKey: string;
  readonly dirs: Array<ImportTreeDirNode> = [];
  readonly files: Array<ImportTreeFileNode> = [];
  parent?: ImportTreeDirNode;
  expanded: boolean = false;
  fileCount: number = 0;
  selectedCount: number = 0;

  constructor(name: string, pathKey: string) {
    this.name = name;
    this.pathKey = pathKey;
  }
}

export interface ImportTreeRow {
  kind: ImportTreeRowKind;
  dir?: ImportTreeDirNode;
  file?: ImportTreeFileNode;
  depth: number;
  key: string;
}

interface ParsedUriEntry {
  uri: string;
  parentSegments: Array<string>;
  fileName: string;
}

const ROOT_FALLBACK_NAME: string = '全部位置';
// Constant docs-provider home prefix shared by every picker URI in a
// session. It is dropped from display segments so the tree roots at a
// meaningful directory instead of the opaque user-home chain.
const HOME_PREFIX_SEGMENTS: Array<string> = ['storage', 'Users', 'currentUser'];

export class ImportUriTree {
  readonly flat: boolean;
  readonly root: ImportTreeDirNode;

  private constructor(flat: boolean, root: ImportTreeDirNode) {
    this.flat = flat;
    this.root = root;
  }

  static build(uris: Array<string>): ImportUriTree {
    const entries: Array<ParsedUriEntry> = [];
    const seen: Set<string> = new Set();
    for (const uri of uris) {
      if (uri.length === 0 || seen.has(uri)) {
        continue;
      }
      seen.add(uri);
      entries.push(ImportUriTree.parseEntry(uri));
    }
    if (entries.length <= 1 || ImportUriTree.shareParent(entries)) {
      return new ImportUriTree(true, ImportUriTree.buildFlatRoot(entries));
    }

    const trieRoot = new ImportTreeDirNode('', '');
    for (const entry of entries) {
      let node = trieRoot;
      for (let depth = 0; depth < entry.parentSegments.length; depth += 1) {
        node = ImportUriTree.childDir(node, entry.parentSegments, depth);
      }
      const file = new ImportTreeFileNode(entry.uri, entry.fileName);
      file.parent = node;
      node.files.push(file);
    }
    ImportUriTree.sortAndAggregate(trieRoot);
    return new ImportUriTree(false, ImportUriTree.locateDisplayRoot(entries, trieRoot));
  }

  get totalCount(): number {
    return this.root.fileCount;
  }

  get selectedCount(): number {
    return this.root.selectedCount;
  }

  checkStateOf(dir: ImportTreeDirNode): ImportTreeCheckState {
    if (dir.selectedCount <= 0 || dir.fileCount <= 0) {
      return ImportTreeCheckState.NONE;
    }
    return dir.selectedCount >= dir.fileCount ? ImportTreeCheckState.ALL : ImportTreeCheckState.PARTIAL;
  }

  toggleDir(dir: ImportTreeDirNode): void {
    const selectAll = dir.selectedCount < dir.fileCount;
    const stack: Array<ImportTreeDirNode> = [dir];
    while (stack.length > 0) {
      const node = stack.pop() as ImportTreeDirNode;
      for (const file of node.files) {
        file.selected = selectAll;
      }
      for (const child of node.dirs) {
        child.selectedCount = selectAll ? child.fileCount : 0;
        stack.push(child);
      }
    }
    const delta = (selectAll ? dir.fileCount : 0) - dir.selectedCount;
    dir.selectedCount = selectAll ? dir.fileCount : 0;
    let ancestor = dir.parent;
    while (ancestor !== undefined) {
      ancestor.selectedCount += delta;
      ancestor = ancestor.parent;
    }
  }

  toggleFile(file: ImportTreeFileNode): void {
    file.selected = !file.selected;
    const delta = file.selected ? 1 : -1;
    let ancestor = file.parent;
    while (ancestor !== undefined) {
      ancestor.selectedCount += delta;
      ancestor = ancestor.parent;
    }
  }

  selectedUris(): Array<string> {
    const selected: Array<string> = [];
    const stack: Array<ImportTreeDirNode> = [this.root];
    while (stack.length > 0) {
      const node = stack.pop() as ImportTreeDirNode;
      for (const file of node.files) {
        if (file.selected) {
          selected.push(file.uri);
        }
      }
      for (const child of node.dirs) {
        stack.push(child);
      }
    }
    return selected;
  }

  visibleRows(): Array<ImportTreeRow> {
    const rows: Array<ImportTreeRow> = [];
    ImportUriTree.appendDirRows(this.root, 0, rows);
    return rows;
  }

  private static appendDirRows(dir: ImportTreeDirNode, depth: number, rows: Array<ImportTreeRow>): void {
    // Mutable visual state is encoded in the key: LazyForEach reuses rows
    // whose keys survive a reload, so a state change must produce a new key
    // for the affected row to be recreated with fresh visuals.
    rows.push({
      kind: ImportTreeRowKind.DIR,
      dir: dir,
      depth: depth,
      key: `d:${dir.pathKey}:${dir.expanded ? 1 : 0}:${dir.selectedCount}`
    });
    if (!dir.expanded) {
      return;
    }
    for (const child of dir.dirs) {
      ImportUriTree.appendDirRows(child, depth + 1, rows);
    }
    for (const file of dir.files) {
      rows.push({
        kind: ImportTreeRowKind.FILE,
        file: file,
        depth: depth + 1,
        key: `f:${file.uri}:${file.selected ? 1 : 0}`
      });
    }
  }

  private static shareParent(entries: Array<ParsedUriEntry>): boolean {
    for (let index = 1; index < entries.length; index += 1) {
      if (!ImportUriTree.sameSegments(entries[0].parentSegments, entries[index].parentSegments)) {
        return false;
      }
    }
    return true;
  }

  private static childDir(parent: ImportTreeDirNode, segments: Array<string>,
    depth: number): ImportTreeDirNode {
    const name = segments[depth];
    const pathKey = segments.slice(0, depth + 1).join('/');
    for (const child of parent.dirs) {
      if (child.name === name && child.pathKey === pathKey) {
        return child;
      }
    }
    const created = new ImportTreeDirNode(name, pathKey);
    created.parent = parent;
    parent.dirs.push(created);
    return created;
  }

  private static sortAndAggregate(dir: ImportTreeDirNode): number {
    let count = dir.files.length;
    for (const child of dir.dirs) {
      count += ImportUriTree.sortAndAggregate(child);
    }
    dir.dirs.sort((left: ImportTreeDirNode, right: ImportTreeDirNode): number =>
      left.name.localeCompare(right.name));
    dir.files.sort((left: ImportTreeFileNode, right: ImportTreeFileNode): number =>
      left.name.localeCompare(right.name));
    dir.fileCount = count;
    dir.selectedCount = count;
    return count;
  }

  private static buildFlatRoot(entries: Array<ParsedUriEntry>): ImportTreeDirNode {
    const parentSegments = entries.length > 0 ? entries[0].parentSegments : [];
    const root = new ImportTreeDirNode(
      parentSegments.length > 0 ? parentSegments[parentSegments.length - 1] : ROOT_FALLBACK_NAME,
      parentSegments.join('/')
    );
    for (const entry of entries) {
      const file = new ImportTreeFileNode(entry.uri, entry.fileName);
      file.parent = root;
      root.files.push(file);
    }
    root.files.sort((left: ImportTreeFileNode, right: ImportTreeFileNode): number =>
      left.name.localeCompare(right.name));
    root.fileCount = root.files.length;
    root.selectedCount = root.files.length;
    root.expanded = true;
    return root;
  }

  private static locateDisplayRoot(entries: Array<ParsedUriEntry>,
    trieRoot: ImportTreeDirNode): ImportTreeDirNode {
    let lcpLength = entries[0].parentSegments.length;
    for (let index = 1; index < entries.length && lcpLength > 0; index += 1) {
      lcpLength = ImportUriTree.commonPrefixLength(entries[0].parentSegments,
        entries[index].parentSegments, lcpLength);
    }
    let displayRoot = trieRoot;
    for (let depth = 0; depth < lcpLength; depth += 1) {
      for (const child of displayRoot.dirs) {
        if (child.name === entries[0].parentSegments[depth]) {
          displayRoot = child;
          break;
        }
      }
    }
    if (displayRoot === trieRoot) {
      displayRoot.name = ROOT_FALLBACK_NAME;
    }
    displayRoot.expanded = true;
    return displayRoot;
  }

  private static parseEntry(uri: string): ParsedUriEntry {
    const segments = ImportUriTree.uriPathSegments(uri);
    if (segments.length === 0) {
      return { uri: uri, parentSegments: [], fileName: uri };
    }
    let parentSegments = segments.slice(0, segments.length - 1);
    if (ImportUriTree.startsWithSegments(parentSegments, HOME_PREFIX_SEGMENTS)) {
      parentSegments = parentSegments.slice(HOME_PREFIX_SEGMENTS.length);
    }
    return {
      uri: uri,
      parentSegments: parentSegments,
      fileName: segments[segments.length - 1]
    };
  }

  /**
   * Extracts display path segments from an authorization-managed URI. The
   * scheme and authority are dropped, query and fragment parts are ignored
   * and each segment is percent-decoded for display. Segments never leave
   * the presentation layer.
   */
  private static uriPathSegments(uri: string): Array<string> {
    let rest = uri;
    const schemeEnd = rest.indexOf('://');
    if (schemeEnd >= 0) {
      rest = rest.substring(schemeEnd + 3);
      const slash = rest.indexOf('/');
      if (slash < 0) {
        return [];
      }
      rest = rest.substring(slash + 1);
    }
    const queryStart = rest.search(/[?#]/);
    if (queryStart >= 0) {
      rest = rest.substring(0, queryStart);
    }
    const segments: Array<string> = [];
    for (const raw of rest.split('/')) {
      if (raw.length > 0) {
        segments.push(ImportUriTree.decodeSegment(raw));
      }
    }
    return segments;
  }

  private static decodeSegment(segment: string): string {
    try {
      return decodeURIComponent(segment);
    } catch (_) {
      return segment;
    }
  }

  private static startsWithSegments(segments: Array<string>, prefix: Array<string>): boolean {
    if (segments.length < prefix.length) {
      return false;
    }
    for (let index = 0; index < prefix.length; index += 1) {
      if (segments[index] !== prefix[index]) {
        return false;
      }
    }
    return true;
  }

  private static sameSegments(left: Array<string>, right: Array<string>): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) {
        return false;
      }
    }
    return true;
  }

  private static commonPrefixLength(left: Array<string>, right: Array<string>,
    limit: number): number {
    const upper = Math.min(limit, right.length);
    let length = 0;
    while (length < upper && left[length] === right[length]) {
      length += 1;
    }
    return length;
  }
}
