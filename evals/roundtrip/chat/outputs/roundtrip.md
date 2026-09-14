It isn't fixed yet. I have a local fix, but I haven't pushed it and CI hasn't run on it.

What happened (verified): `test-integration` has been failing since commit `a41c9e2`, "bump httpx to 0.28", merged yesterday at 15:12. The failure is `tests/test_upload.py::test_large_file` with `TimeoutError after 30.0s`. httpx 0.28 changed the default timeout for streamed uploads from none to 5 seconds per chunk. The test uploads a 200 MB file to a throttled local server, so its chunks now hit that limit.

The fix (verified locally): I set `timeout=None` on the upload client in `src/uploader/client.py`. `pytest tests/test_upload.py` passes, 14 of 14.

Not checked:
- The rest of the integration suite. It needs credentials I don't have, so I haven't run it.
- Production uploads. Production uses the same client, so hypothesis: slow production uploads could hit the same 5-second chunk timeout. I have not looked.

Proposal: push the change so CI runs the full `test-integration` job on it. Separately, check whether production uploads have been timing out since the httpx 0.28 deploy.
