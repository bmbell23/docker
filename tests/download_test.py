#!/usr/bin/env python3
"""scripts/download/download.py against fake Jackett/qBittorrent (docker#177).
Run: python3 tests/download_test.py   (no network, no containers)"""
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("download", HERE / "scripts/download/download.py")
dl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dl)

GC_ISO = b"GALE01" + b"\0" * 0x16 + b"\xc2\x33\x9f\x3d" + b"\0" * 64
OTHER_ISO = b"\0" * 0x40


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        dl.STATE = self.tmp / "state"
        dl.MEDIA = self.tmp / "media"
        dl.TORRENTS_HOST = dl.MEDIA / "downloads/torrents"
        dl.TORRENTS_HOST.mkdir(parents=True)
        dl.SAY = str(self.tmp / "no-say")
        self.calls = []
        self.torrents = []

        def fake_qbit(path, fields=None, stdin_url=None):
            self.calls.append((path, fields, stdin_url))
            return json.dumps(self.torrents) if path.startswith("torrents/info") else "Ok."
        dl.qbit = fake_qbit


class Search(Base):
    def results(self):
        return [
            {"Title": "Low", "Seeders": 3, "Size": 1 << 30, "Tracker": "a", "MagnetUri": "magnet:?low", "Category": [2000]},
            {"Title": "High", "Seeders": 900, "Size": 5 << 30, "Tracker": "b", "Link": "http://j/dl?apikey=SECRET", "Category": [5040]},
            {"Title": "NoLink", "Seeders": 9999, "Size": 1, "Tracker": "c", "Category": [2000]},
        ] + [{"Title": f"M{i}", "Seeders": 10 + i, "Size": 1, "Tracker": "d", "MagnetUri": f"magnet:?{i}", "Category": [3030]} for i in range(6)]

    def test_sorted_top5_and_saved(self):
        seen = {}
        dl.jackett_search = lambda q, c: seen.update(q=q, c=c) or (self.results(), [])
        out = dl.main(["melee", "game"])
        self.assertEqual(seen, {"q": "melee", "c": "game"})
        self.assertIn("1. **High**", out)
        self.assertNotIn("NoLink", out)          # nothing to download
        self.assertNotIn("SECRET", out)          # Jackett links hold the key
        saved = json.loads((dl.STATE / "last.json").read_text())
        self.assertEqual(len(saved), 5)
        self.assertEqual(saved[0]["category"], "game")   # the search category wins

    def test_no_category_uses_result_ids(self):
        dl.jackett_search = lambda q, c: (self.results(), [])
        out = dl.main(["dune", "part", "two"])
        self.assertIn('"dune part two"', out)
        saved = json.loads((dl.STATE / "last.json").read_text())
        self.assertEqual(saved[0]["category"], "tv")          # 5040
        self.assertEqual(saved[1]["category"], "audiobook")   # 3030

    def test_aliases_and_ids(self):
        self.assertEqual(dl.category_of("Movies"), "movie")
        self.assertIsNone(dl.category_of("melee"))
        self.assertEqual(dl.category_from_ids([7020]), "book")
        self.assertEqual(dl.category_from_ids([4050]), "game")
        self.assertEqual(dl.category_from_ids([3010]), "music")
        self.assertIsNone(dl.category_from_ids([100123]))

    def test_pick_sends_url_on_stdin(self):
        dl.jackett_search = lambda q, c: (self.results(), [])
        dl.main(["x"])
        out = dl.main(["1"])
        path, fields, url = self.calls[-1]
        self.assertEqual((path, fields), ("torrents/add", {"category": "dl-tv"}))
        self.assertEqual(url, "http://j/dl?apikey=SECRET")
        self.assertIn("Downloading **High**", out)
        self.assertIn("Pick 1–5", dl.main(["9"]))

    def test_pick_without_search(self):
        self.assertIn("No search", dl.main(["2"]))

    def test_help(self):
        out = dl.main(["help"])
        for c in dl.CATEGORIES:
            self.assertIn(f"`{c}`", out)


INDEXERS_XML = b"""<indexers>
<indexer id="audiobookbay" configured="true"><title>AudioBook Bay</title><caps><categories>
  <category id="3000"><subcat id="3030"/></category></categories></caps></indexer>
<indexer id="tpb" configured="true"><title>The Pirate Bay</title><caps><categories>
  <category id="2000"/><category id="3000"/><category id="5000"/></categories></caps></indexer>
<indexer id="dead" configured="true"><title>Dead One</title><caps><categories>
  <category id="2000"/></categories></caps></indexer>
</indexers>"""


class Indexers(Base):
    """docker#182: one hanging indexer must not sink the search, and gets named."""
    def setUp(self):
        super().setUp()
        dl.KEY_FILE = self.tmp / "key"
        dl.KEY_FILE.write_text("SECRET\n")
        self.asked = []

        def fake_get(path, params, timeout):
            self.asked.append(path)
            if "torznab" in path:
                return INDEXERS_XML
            if "/dead/" in path:
                raise TimeoutError("timed out")
            return json.dumps({"Results": [{"Title": path, "Seeders": 5, "MagnetUri": "magnet:?x", "Category": [2000]}]}).encode()
        dl.jackett_get = fake_get

    def test_category_skips_indexers_without_it(self):
        self.assertEqual([i for i, _ in dl.indexers_for("movie")], ["tpb", "dead"])
        self.assertEqual([i for i, _ in dl.indexers_for("audiobook")], ["audiobookbay", "tpb"])
        self.assertEqual(len(dl.indexers_for(None)), 3)

    def test_dead_indexer_skipped_and_named(self):
        out = dl.main(["10", "things", "i", "hate", "about", "you", "movie"])
        self.assertIn("indexers/tpb/results", out)              # the live one answered
        self.assertIn("Skipped: Dead One (no answer in", out)
        self.assertNotIn("audiobookbay", " ".join(self.asked))  # not asked for a movie
        self.assertNotIn("VPN", out)

    def test_jackett_down_blames_jackett(self):
        def down(path, params, timeout):
            raise OSError("refused")
        dl.jackett_get = down
        with self.assertRaises(SystemExit):
            dl.main(["dune", "movie"])


class Place(Base):
    def torrent(self, name, cat, data=b"x", tags=""):
        p = dl.TORRENTS_HOST / name
        p.write_bytes(data)
        self.torrents.append({"name": name, "hash": name, "category": cat, "tags": tags,
                              "content_path": f"/downloads/{name}"})
        return p

    def test_movie_hardlinked_and_tagged(self):
        src = self.torrent("Film.mkv", "dl-movie")
        dl.main(["place"])
        dest = dl.MEDIA / "videos/movies/Film.mkv"
        self.assertTrue(dest.exists())
        self.assertEqual(os.stat(src).st_ino, os.stat(dest).st_ino)   # a link, not a copy
        self.assertIn(("torrents/addTags", {"hashes": "Film.mkv", "tags": "placed"}, None), self.calls)

    def test_gamecube_iso_by_header(self):
        self.torrent("Melee.iso", "dl-game", GC_ISO)
        self.torrent("Mystery.iso", "dl-game", OTHER_ISO)
        self.torrent("Zelda.gba", "dl-game")
        dl.main(["place"])
        self.assertTrue((dl.MEDIA / "games/ngc/Melee.iso").exists())
        self.assertTrue((dl.MEDIA / "games/gba/Zelda.gba").exists())
        self.assertTrue((dl.MEDIA / "games-staging/Mystery.iso").exists())

    def test_folder_torrent(self):
        d = dl.TORRENTS_HOST / "Album"
        (d / "cd1").mkdir(parents=True)
        (d / "cd1/01.flac").write_bytes(b"a")
        (d / "02.flac").write_bytes(b"b")
        self.torrents.append({"name": "Album", "hash": "h", "category": "dl-music", "tags": "",
                              "content_path": "/downloads/Album"})
        dl.main(["place"])
        self.assertTrue((dl.MEDIA / "music/Album/cd1/01.flac").exists())
        self.assertTrue((dl.MEDIA / "music/Album/02.flac").exists())

    def test_skips_placed_and_foreign(self):
        self.torrent("Old.mkv", "dl-movie", tags="placed")
        self.torrent("Mine.mkv", "")          # added by hand, not by !download
        dl.main(["place"])
        self.assertFalse((dl.MEDIA / "videos/movies").exists())
        self.assertEqual([c for c in self.calls if c[0] == "torrents/addTags"], [])

    def test_missing_file_retried(self):
        self.torrents.append({"name": "Gone", "hash": "g", "category": "dl-tv", "tags": "",
                              "content_path": "/downloads/Gone"})
        dl.main(["place"])
        self.assertEqual([c for c in self.calls if c[0] == "torrents/addTags"], [])

    def folder(self, name, cat, files):
        d = dl.TORRENTS_HOST / name
        for rel, data in files.items():
            (d / rel).parent.mkdir(parents=True, exist_ok=True)
            (d / rel).write_bytes(data)
        self.torrents.append({"name": name, "hash": name, "category": cat, "tags": "",
                              "content_path": f"/downloads/{name}"})

    def test_movie_clean_name_and_junk_dropped(self):   # docker#180: the Mario download
        rel = "The Super Mario Bros Movie 2023 UHD BluRay 1080p DD Atmos 5 1 DoVi HDR10 x265-SM737"
        name = f"www.UIndex.org    -    {rel}"
        self.folder(name, "dl-movie", {f"{rel}.mkv": b"v" * 100, f"{rel}.mkv.nfo": b"n",
                                       f"{rel}.en.srt": b"s", "Sample/sample.mkv": b"x",
                                       "Torrent Downloaded From     UIndex.org      .txt": b"t"})
        dl.main(["place"])
        d = dl.MEDIA / "videos/movies/The Super Mario Bros Movie (2023)"
        self.assertEqual(sorted(p.name for p in d.rglob("*") if p.is_file()),
                         ["The Super Mario Bros Movie (2023).en.srt", "The Super Mario Bros Movie (2023).mkv"])

    def test_names(self):
        self.assertEqual(dl.movie_name("Blade.Runner.2049.2017.2160p.x265-GRP.mkv"), "Blade Runner 2049 (2017)")
        self.assertEqual(dl.movie_name("1917 (2019) [1080p] [YTS.MX]"), "1917 (2019)")
        self.assertEqual(dl.movie_name("[YTS.MX] Clueless (1995) [BluRay]"), "Clueless (1995)")
        self.assertEqual(dl.movie_name("Back To The Future Trilogy 1985,1989,1990 Remastered 1080p"),
                         "Back To The Future Trilogy (1985)")
        self.assertIsNone(dl.movie_name("Film.mkv"))
        self.assertEqual(dl.show_name("The.Office.US.S02E03.720p.WEB"), ("The Office US", 2))
        self.assertEqual(dl.show_name("Doctor.Who.2005.S01.COMPLETE.1080p"), ("Doctor Who (2005)", 1))
        self.assertEqual(dl.show_name("Bluey Season 3 1080p"), ("Bluey", 3))
        self.assertIsNone(dl.show_name("Some Documentary 1080p"))

    def test_tv_season_folders(self):
        self.folder("Bluey.S01-S02.1080p", "dl-tv", {"Bluey.S01E01.mkv": b"a", "S2/Bluey.S02E05.mkv": b"b",
                                                    "info.nfo": b"n"})
        dl.main(["place"])
        d = dl.MEDIA / "videos/shows/Bluey"
        self.assertTrue((d / "Season 01/Bluey.S01E01.mkv").exists())
        self.assertTrue((d / "Season 02/Bluey.S02E05.mkv").exists())
        self.assertFalse(list(d.rglob("*.nfo")))

    def test_unreadable_name_falls_back(self):
        self.torrent("Mystery Film.mkv", "dl-movie")
        dl.main(["place"])
        self.assertTrue((dl.MEDIA / "videos/movies/Mystery Film.mkv").exists())


if __name__ == "__main__":
    sys.stderr = open(os.devnull, "w") if "-q" in sys.argv else sys.stderr
    unittest.main(argv=[sys.argv[0]])
