package com.dylanvann.fastimage.transformations;

import android.content.Context;
import android.graphics.Bitmap;
import android.renderscript.Allocation;
import android.renderscript.Element;
import android.renderscript.RenderScript;
import android.renderscript.ScriptIntrinsicBlur;
import android.widget.ImageView;

import androidx.annotation.Nullable;

@SuppressWarnings("deprecation")
public class FastImageBlurScriptEngine {
    private static final float BLUR_REFERENCE_SIZE = 540f;
    private static final float BLUR_MIN_SCALE = 0.1f;
    private static final float BLUR_MAX_SCALE = 1.5F;
    private static final float BLUR_LIMIT_APPLICABLE_AT_ONCE = 25f;

    /**
     * Gradual blur is applied to achieve a RenderEffect-like blur.
     */
    public static Bitmap apply(Bitmap src, float radius, Context context) {
        // If the image is small, the blur will be more effective.
        // By scaling it down, the blur effect is intensified.
        float scaleX = BLUR_REFERENCE_SIZE / src.getWidth();
        float scaleY = BLUR_REFERENCE_SIZE / src.getHeight();
        float scale = (scaleX + scaleY) / 2;
        float scaleNormalized = Math.min(BLUR_MAX_SCALE, Math.max(BLUR_MIN_SCALE, scale));

        int width = (int) (src.getWidth() * scaleNormalized);
        int height = (int) (src.getHeight() * scaleNormalized);
        Bitmap bitmap = Bitmap.createScaledBitmap(src, width, height, true);

        // Blur is applied piece by piece, the whole piece.
        int stages = (int) Math.ceil(radius / BLUR_LIMIT_APPLICABLE_AT_ONCE);
        float stageRadius = radius / stages;
        for (int i = 0; i < stages; i++) {
            bitmap = blur(bitmap, stageRadius, context);
        }

        return Bitmap.createScaledBitmap(bitmap, src.getWidth(), src.getHeight(), true);
    }

    /**
     * Used to create blur with RenderScript.
     * With RenderScript, blur can be applied at a maximum level of 25f at a time.
     */
    static Bitmap blur(Bitmap src, float radius, Context context) {
        Bitmap.Config config = src.getConfig() != null ? src.getConfig() : Bitmap.Config.ARGB_8888;
        Bitmap bitmap = src.copy(config, true);

        RenderScript rs = null;
        Allocation input = null;
        Allocation output = null;
        ScriptIntrinsicBlur blur = null;

        try {
            rs = RenderScript.create(context);
            input = Allocation.createFromBitmap(rs, bitmap);
            output = Allocation.createTyped(rs, input.getType());
            blur = ScriptIntrinsicBlur.create(rs, Element.U8_4(rs));

            blur.setRadius(radius);
            blur.setInput(input);
            blur.forEach(output);
            output.copyTo(bitmap);

        } catch (Exception e) {
            return src;
        } finally {
            if (blur != null) blur.destroy();
            if (input != null) input.destroy();
            if (output != null) output.destroy();
            if (rs != null) rs.destroy();
        }

        return bitmap;
    }


    /**
     * No cleanup is required for RenderScript.
     * Just the placeholder for consistency.
     */
    public static void clean(@Nullable ImageView view) {}
}
