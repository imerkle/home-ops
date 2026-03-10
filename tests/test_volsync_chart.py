import pathlib
import subprocess
import unittest

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[1]
CHART = ROOT / "charts" / "volsync"
FIXTURES = ROOT / "tests" / "fixtures"


class VolsyncChartTests(unittest.TestCase):
    maxDiff = None

    def render(self, fixture_name: str, app: str):
        result = subprocess.run(
            [
                "helm",
                "template",
                f"{app}-volsync",
                str(CHART),
                "-f",
                str(FIXTURES / fixture_name),
                "--set",
                f"app={app}",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return [doc for doc in yaml.safe_load_all(result.stdout) if doc]

    def test_renders_single_pvc_bundle(self):
        documents = self.render("volsync-single.yaml", "forgejo")

        self.assertEqual(
            [doc["kind"] for doc in documents],
            [
                "Secret",
                "PersistentVolumeClaim",
                "ReplicationDestination",
                "ReplicationSource",
            ],
        )
        self.assertEqual(documents[0]["metadata"]["name"], "forgejo-volsync-secret")
        self.assertEqual(documents[1]["metadata"]["name"], "forgejo")
        self.assertEqual(documents[1]["spec"]["dataSourceRef"]["name"], "forgejo-dst")
        self.assertEqual(documents[2]["metadata"]["name"], "forgejo-dst")
        self.assertEqual(documents[2]["spec"]["kopia"]["repository"], "forgejo-volsync-secret")
        self.assertEqual(documents[3]["metadata"]["name"], "forgejo")
        self.assertEqual(documents[3]["spec"]["sourcePVC"], "forgejo")

    def test_renders_multiple_pvc_bundles(self):
        documents = self.render("volsync-multi.yaml", "home-assistant")

        self.assertEqual(len(documents), 8)

        pvc_documents = {
            doc["metadata"]["name"]: doc
            for doc in documents
            if doc["kind"] == "PersistentVolumeClaim"
        }
        self.assertEqual(set(pvc_documents), {"home-assistant", "home-assistant-cache"})
        self.assertEqual(
            pvc_documents["home-assistant"]["spec"]["resources"]["requests"]["storage"],
            "5Gi",
        )
        self.assertEqual(
            pvc_documents["home-assistant-cache"]["spec"]["resources"]["requests"]["storage"],
            "1Gi",
        )

        source_documents = {
            doc["metadata"]["name"]: doc
            for doc in documents
            if doc["kind"] == "ReplicationSource"
        }
        self.assertEqual(set(source_documents), {"home-assistant", "home-assistant-cache"})
        self.assertEqual(
            source_documents["home-assistant-cache"]["spec"]["sourcePVC"],
            "home-assistant-cache",
        )
        self.assertEqual(
            source_documents["home-assistant-cache"]["spec"]["kopia"]["repository"],
            "home-assistant-cache-volsync-secret",
        )


if __name__ == "__main__":
    unittest.main()
