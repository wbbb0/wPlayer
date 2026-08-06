import { describe, expect, it } from '@ohos/hypium';
import {
  ImportTreeCheckState,
  ImportTreeDirNode,
  ImportTreeFileNode,
  ImportTreeRow,
  ImportTreeRowKind,
  ImportUriTree
} from '../main/ets/library/importer/ImportUriTree';

const PREFIX: string = 'file://docs/storage/Users/currentUser/';

function docUri(path: string): string {
  return `${PREFIX}${path}`;
}

function dirRowKeys(tree: ImportUriTree): Array<string> {
  const keys: Array<string> = [];
  for (const row of tree.visibleRows()) {
    if (row.kind === ImportTreeRowKind.DIR && row.dir !== undefined) {
      keys.push(row.dir.name);
    }
  }
  return keys;
}

function findDir(root: ImportTreeDirNode, name: string): ImportTreeDirNode | undefined {
  const stack: Array<ImportTreeDirNode> = [root];
  while (stack.length > 0) {
    const node = stack.pop() as ImportTreeDirNode;
    if (node.name === name) {
      return node;
    }
    for (const child of node.dirs) {
      stack.push(child);
    }
  }
  return undefined;
}

export default function importUriTreeTest() {
  describe('Import URI tree', () => {
    it('is flat when every URI shares the same parent directory', 0, () => {
      const tree = ImportUriTree.build([
        docUri('Music/a.mp3'),
        docUri('Music/b.flac'),
        docUri('Music/c.mp3')
      ]);
      expect(tree.flat).assertTrue();
      expect(tree.totalCount).assertEqual(3);
      expect(tree.selectedCount).assertEqual(3);
    });

    it('is flat for a single URI and for duplicate-only input', 0, () => {
      expect(ImportUriTree.build([docUri('Music/a.mp3')]).flat).assertTrue();
      const tree = ImportUriTree.build([docUri('Music/a.mp3'), docUri('Music/a.mp3')]);
      expect(tree.flat).assertTrue();
      expect(tree.totalCount).assertEqual(1);
    });

    it('roots the tree at the earliest diverging directory', 0, () => {
      const tree = ImportUriTree.build([
        docUri('Music/ArtistA/Album1/01.mp3'),
        docUri('Music/ArtistA/Album2/01.mp3'),
        docUri('Music/ArtistB/01.flac')
      ]);
      expect(tree.flat).assertFalse();
      expect(tree.root.name).assertEqual('Music');
      expect(tree.root.fileCount).assertEqual(3);
      expect(dirRowKeys(tree)).assertEqual('Music,ArtistA,ArtistB'.split(','));
    });

    it('uses a fallback root name when directories diverge at the top level', 0, () => {
      const tree = ImportUriTree.build([
        docUri('Music/a.mp3'),
        docUri('Download/b.mp3')
      ]);
      expect(tree.flat).assertFalse();
      expect(tree.root.name).assertEqual('全部位置');
      expect(tree.root.fileCount).assertEqual(2);
    });

    it('decodes percent-encoded path segments for display only', 0, () => {
      const encoded = `${PREFIX}Music/%E5%91%A8%E6%9D%B0%E4%BC%A6/%E6%99%B4%E5%A4%A9.flac`;
      const tree = ImportUriTree.build([encoded, docUri('Music/other/x.mp3')]);
      expect(tree.flat).assertFalse();
      const jay = findDir(tree.root, '周杰伦');
      expect(jay !== undefined).assertTrue();
      const file = (jay as ImportTreeDirNode).files[0];
      expect(file.name).assertEqual('晴天.flac');
      expect(file.uri).assertEqual(encoded);
    });

    it('groups URIs without a path structure at the root instead of failing', 0, () => {
      const tree = ImportUriTree.build(['about:blank', docUri('Music/a.mp3')]);
      expect(tree.flat).assertFalse();
      expect(tree.root.name).assertEqual('全部位置');
      expect(tree.root.files.length).assertEqual(1);
      expect(tree.root.files[0].name).assertEqual('about:blank');
    });

    it('ignores query and fragment parts when grouping', 0, () => {
      const tree = ImportUriTree.build([
        `${docUri('Music/a.mp3')}?foo=1`,
        `${docUri('Music/b.mp3')}#frag`
      ]);
      expect(tree.flat).assertTrue();
      expect(tree.totalCount).assertEqual(2);
    });

    it('toggles a directory across its whole subtree and updates ancestors', 0, () => {
      const tree = ImportUriTree.build([
        docUri('Music/ArtistA/Album1/01.mp3'),
        docUri('Music/ArtistA/Album2/01.mp3'),
        docUri('Music/ArtistB/01.flac')
      ]);
      const artistA = findDir(tree.root, 'ArtistA') as ImportTreeDirNode;
      expect(tree.checkStateOf(artistA)).assertEqual(ImportTreeCheckState.ALL);

      tree.toggleDir(artistA);
      expect(tree.checkStateOf(artistA)).assertEqual(ImportTreeCheckState.NONE);
      expect(tree.selectedCount).assertEqual(1);
      expect(tree.checkStateOf(tree.root)).assertEqual(ImportTreeCheckState.PARTIAL);

      tree.toggleDir(artistA);
      expect(tree.checkStateOf(artistA)).assertEqual(ImportTreeCheckState.ALL);
      expect(tree.selectedCount).assertEqual(3);
      expect(tree.checkStateOf(tree.root)).assertEqual(ImportTreeCheckState.ALL);
    });

    it('derives partial state from single file toggles', 0, () => {
      const tree = ImportUriTree.build([
        docUri('Music/ArtistA/01.mp3'),
        docUri('Music/ArtistA/02.mp3'),
        docUri('Music/ArtistB/01.flac')
      ]);
      const artistA = findDir(tree.root, 'ArtistA') as ImportTreeDirNode;
      const file = artistA.files[0] as ImportTreeFileNode;
      tree.toggleFile(file);
      expect(tree.checkStateOf(artistA)).assertEqual(ImportTreeCheckState.PARTIAL);
      expect(tree.checkStateOf(tree.root)).assertEqual(ImportTreeCheckState.PARTIAL);
      tree.toggleFile(file);
      expect(tree.checkStateOf(artistA)).assertEqual(ImportTreeCheckState.ALL);
    });

    it('collects only selected URIs in stable subtree coverage', 0, () => {
      const tree = ImportUriTree.build([
        docUri('Music/ArtistA/01.mp3'),
        docUri('Music/ArtistA/02.mp3'),
        docUri('Music/ArtistB/01.flac')
      ]);
      const artistA = findDir(tree.root, 'ArtistA') as ImportTreeDirNode;
      tree.toggleDir(artistA);
      const selected = tree.selectedUris();
      expect(selected.length).assertEqual(1);
      expect(selected[0]).assertEqual(docUri('Music/ArtistB/01.flac'));
    });

    it('lists only expanded branches as visible rows', 0, () => {
      const tree = ImportUriTree.build([
        docUri('Music/ArtistA/01.mp3'),
        docUri('Music/ArtistA/02.mp3'),
        docUri('Music/ArtistB/01.flac')
      ]);
      // Root is expanded by default, child directories stay collapsed.
      expect(tree.visibleRows().length).assertEqual(3);
      const artistA = findDir(tree.root, 'ArtistA') as ImportTreeDirNode;
      artistA.expanded = true;
      const rows = tree.visibleRows();
      expect(rows.length).assertEqual(5);
      const fileRows = rows.filter((row: ImportTreeRow): boolean => row.kind === ImportTreeRowKind.FILE);
      expect(fileRows.length).assertEqual(2);
      expect(fileRows[0].depth).assertEqual(2);
    });

    it('builds and toggles picker-scale input without quadratic blowups', 0, () => {
      const uris: Array<string> = [];
      for (let dir = 0; dir < 200; dir += 1) {
        for (let file = 0; file < 295; file += 1) {
          uris.push(docUri(`Music/dir${dir}/track${file}.mp3`));
        }
      }
      const startedAt = Date.now();
      const tree = ImportUriTree.build(uris);
      const music = tree.root;
      tree.toggleDir(music);
      tree.toggleDir(music);
      const elapsed = Date.now() - startedAt;
      expect(tree.totalCount).assertEqual(59000);
      expect(tree.selectedCount).assertEqual(59000);
      expect(elapsed < 5000).assertTrue();
    });
  });
}
