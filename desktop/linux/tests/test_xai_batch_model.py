from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from echoscribe.http_client import HttpResponse
from echoscribe.providers import XAIProvider


class XaiBatchModelTests(unittest.TestCase):
    def test_explicit_batch_model_is_sent_in_multipart_fields(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            audio = Path(raw) / "synthetic.wav"
            audio.write_bytes(b"RIFFsynthetic")
            with patch(
                "echoscribe.providers.post_multipart",
                return_value=HttpResponse(200, b'{"text":"Erkannt"}', {}),
            ) as request:
                result = XAIProvider("unit-test-key").transcribe(
                    audio, model="grok-voice-transcribe-2.0"
                )
            self.assertEqual(result, "Erkannt")
            self.assertEqual(request.call_args.args[0], "https://api.x.ai/v1/stt")
            self.assertEqual(
                request.call_args.kwargs["fields"],
                {"model": "grok-voice-transcribe-2.0", "format": "false"},
            )


if __name__ == "__main__":
    unittest.main()
