# Integration tests

These tests hit a real running server. Start the Go backend first, then run:

```bash
flutter test test/core/net_engine/relay_v3_integration_test.dart \
  --dart-define=RELAY_URL=http://127.0.0.1:8000
```

If `RELAY_URL` is not set, defaults to `http://127.0.0.1:8000`.