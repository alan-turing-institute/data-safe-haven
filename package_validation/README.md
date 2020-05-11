# Package validator

- [x] Reference the tier3_cran_whitelist.list and tier3_pypi_whitelist.list whitelist files at environment_configs/package_lists directly rather than having local copies.
- [ ] Add a README.md with instructions for configuring the environment and running the script.
- [ ] Add some tests.
- [ ] Add a note on timings for expanding each of the whitelists.
- [ ] Add a `tier3_<platform>_whitelist_expansion_log.json` file with the sha256 hash of the initial and expanded whitelists.
- [ ] Refactor of the key handler to receive the keys and form the handler in memory.
- [ ] Use the s in a `x-ratelimit-limit` HTTP header for 200 responses and the `retry-after` HTTP header field for rate limited 429 responses.
- [ ] Check if 
- Repo containing 1) whitelist-core, 2) whitelist-full, 3) script to turn core into full.

`json` Output:
```
timestamp: "YYYY-MM-DDThh:mm:ssZ"
core_filename: "tier3_cran_whitelist_core.list"
core_sha256: "a8ebfff7e54ebc78642cd671d142d18bba262109d1c2d83caf5a4a999fec9673"
expanded_filename: "tier3_cran_whitelist_expanded.list"
expanded_sha256: "bde5356a03bbf591a6fe0a93f379fa477692480d9328227808465d638080339b"
num_core_packages: "57"
num_expanded_packages: "234"
elapsed_time: "34h22m47s"
```