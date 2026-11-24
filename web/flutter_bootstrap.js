{{flutter_js}}
{{flutter_build_config}}
const config = {hostElement: document.getElementById('flutter-host')};
_flutter.loader.load({
  config,
  onEntrypointLoaded: async initializer => {
    try {
      const runner = await initializer.initializeEngine(config);
      await runner.runApp();
      window.amidPwa.startupReady();
    } catch (_) { window.amidPwa.startupError(); }
  }
}).catch(() => window.amidPwa.startupError());
