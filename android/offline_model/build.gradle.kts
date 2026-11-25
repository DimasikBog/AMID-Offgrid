plugins {
    id("com.android.ai-pack")
}

aiPack {
    packName = "offline_model"
    dynamicDelivery {
        deliveryType = "install-time"
    }
}
