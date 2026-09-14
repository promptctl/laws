Not fixed yet. I have a fix, but it's only on my machine so far.

**What broke:** `test-integration` has been failing since `a41c9e2` ("bump httpx to 0.28"), which merged yesterday at 15:12. The failure is `tests/test_upload.py::test_large_file` with `TimeoutError after 30.0s`.

**Why:** httpx 0.28 changed the default timeout for streamed uploads. It used to be no timeout. Now it's 5 seconds per chunk. That test uploads a 200 MB file to a throttled local server, so chunks now take longer than 5 seconds and time out.

**What I changed:** I set `timeout=None` explicitly on the upload client in `src/uploader/client.py`. With that change, `pytest tests/test_upload.py` passes locally, all 14 tests.

**Not done yet:**
- I haven't pushed the change, so CI hasn't run on it. CI is still red.
- I couldn't run the rest of the integration suite locally because it needs credentials I don't have. I don't know yet whether anything else in it is affected.
- I haven't checked production. Production uses the same upload client, so if it's on httpx 0.28, large or slow uploads could be hitting the same 5-second chunk timeout. I haven't confirmed that either way.

Want me to push the fix so CI can run the full suite? Separately, it's worth checking whether production has deployed the httpx bump.
