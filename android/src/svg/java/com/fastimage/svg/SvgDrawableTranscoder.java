package com.fastimage.svg;

import android.graphics.Picture;
import android.graphics.drawable.PictureDrawable;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import com.bumptech.glide.load.Options;
import com.bumptech.glide.load.engine.Resource;
import com.bumptech.glide.load.resource.SimpleResource;
import com.bumptech.glide.load.resource.transcode.ResourceTranscoder;
import com.caverock.androidsvg.SVG;

/**
 * Convert the {@link SVG}'s internal representation to an Android-compatible one ({@link Picture}).
 * Copied from https://github.com/bumptech/glide/blob/10acc31a16b4c1b5684f69e8de3117371dfa77a8/samples/svg/src/main/java/com/bumptech/glide/samples/svg/SvgDrawableTranscoder.java
 */
public class SvgDrawableTranscoder implements ResourceTranscoder<SVG, PictureDrawable> {
  @Nullable
  @Override
  public Resource<PictureDrawable> transcode(
      @NonNull Resource<SVG> toTranscode, @NonNull Options options) {
    SVG svg = toTranscode.get();
    Picture picture = svg.renderToPicture();
    PictureDrawable drawable = new PictureDrawable(picture);
    return new SimpleResource<>(drawable);
  }
}