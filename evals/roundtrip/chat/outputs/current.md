It's not fixed in CI yet. I have a fix that passes locally, but I haven't pushed it.

What happened: `test-integration` began failing at `a41c9e2` ("bump httpx to 0.28"), which was merged yesterday at 15:12. The failure is `tests/test_upload.py::test_large_file` with `TimeoutError after 30.0s`.

The cause: httpx 0.28 changed the default timeout for streamed uploads from none to 5 seconds per chunk. The test uploads a 200 MB file to a throttled local server, so each chunk now takes longer than 5 seconds and times out.

The fix: I set `timeout=None` explicitly on the upload client in `src/uploader/client.py`. With that change, all 14 tests in `pytest tests/test_upload.py` pass locally.

Not verified yet:
- CI hasn't run on the change, because it isn't pushed.
- I only ran `tests/test_upload.py`. The rest of the integration suite needs credentials I don't have.
- Production uses the same client, and I didn't check whether production uploads are affected. My guess, which I haven't tested, is that large production uploads over slow links could hit the same 5-second chunk timeout.

Proposal: I push the change so CI runs the full integration suite. Separately, someone should check production upload errors since yesterday's deploy of `a41c9e2`, if it has been deployed. That would tell us whether this is only a test failure or a live bug.
