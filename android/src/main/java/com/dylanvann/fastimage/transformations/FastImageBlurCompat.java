package com.dylanvann.fastimage.transformations;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.Build;
import android.widget.ImageView;

import androidx.annotation.Nullable;

public class FastImageBlurCompat {
    /**
     * For Android API >= 31, blur is applied using RenderEffect directly on the View.
     * For Android API < 31, blur is applied using RenderScript on the Bitmap.
     * This ensures compatibility with both legacy and future Android versions.
     */
    public static Bitmap blur(Context context, Bitmap bitmap, float radius, ImageView view) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return FastImageBlurEffectEngine.apply(bitmap, radius, view);
        } else {
            return FastImageBlurScriptEngine.apply(bitmap, radius, context);
        }
    }

    public static void clean(@Nullable ImageView view) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            FastImageBlurEffectEngine.clean(view);
        } else {
            FastImageBlurScriptEngine.clean(view);
        }
    }
}
