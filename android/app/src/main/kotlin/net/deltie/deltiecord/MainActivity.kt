package net.deltie.deltiecord

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.unifiedpush.android.connector.UnifiedPush

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "net.deltie.deltiecord/unified_push"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val instance = call.argument<String>("instance") ?: "default"
                when (call.method) {
                    "getDistributors" -> result.success(UnifiedPush.getDistributors(this))
                    "getState" -> result.success(DeltiecordPushService.state(this, instance))
                    "selectDistributor" -> {
                        val distributor = call.argument<String>("distributor")
                        if (distributor.isNullOrBlank()) {
                            result.error("invalid_distributor", "Choose a UnifiedPush distributor.", null)
                        } else {
                            UnifiedPush.saveDistributor(this, distributor)
                            // An endpoint belongs to the selected distributor.
                            // Never reuse a stale capability after switching.
                            DeltiecordPushService.clear(this, instance)
                            UnifiedPush.register(
                                this,
                                instance,
                                messageForDistributor = "Deltiecord Matrix notifications",
                            )
                            result.success(null)
                        }
                    }
                    "register" -> {
                        if (UnifiedPush.getSavedDistributor(this) == null) {
                            result.error("no_distributor", "No UnifiedPush distributor is selected.", null)
                        } else {
                            UnifiedPush.register(
                                this,
                                instance,
                                messageForDistributor = "Deltiecord Matrix notifications",
                            )
                            result.success(null)
                        }
                    }
                    "unregister" -> {
                        UnifiedPush.unregister(this, instance)
                        DeltiecordPushService.clear(this, instance)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
