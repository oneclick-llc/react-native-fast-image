package com.dylanvann.fastimage;

import android.content.Context;

import androidx.annotation.NonNull;

import com.bumptech.glide.load.Key;
import com.bumptech.glide.load.engine.cache.DiskCache;
import com.bumptech.glide.load.engine.cache.InternalCacheDiskCacheFactory;

import java.io.File;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

//public class ExtraDiskCache implements DiskCache.Factory {
//
//  @Nullable
//  @Override
//  public DiskCache build() {
//    return null;
//  }
//}

public class ExtraDiskCacheAdapter implements DiskCache {
  public static final String DEFAULT_TIER_NAME = "primary";
  public static final String TIER_PREFIX = "ch-tier-";
  private static final Pattern SOURCE_PATTERN = Pattern.compile("sourceKey=([^,]+),");
  private static final Pattern SOURCE_CACHE_TIER_PATTERN = Pattern.compile("#" + TIER_PREFIX + "-(.*)");
  private static final Map<String, DiskCache> tiers = new HashMap<>();

  @Override
  public File get(Key key) {
    return this.getActualCache(key).get(key);
  }

  @Override
  public void put(Key key, Writer writer) {
    this.getActualCache(key).put(key, writer);
  }

  @Override
  public void delete(Key key) {
    this.getActualCache(key).delete(key);
  }

  @Override
  public void clear() {
    ExtraDiskCacheAdapter.tiers.values().forEach(DiskCache::clear);
  }

  private DiskCache getActualCache(Key key) {
//    String tierKey = key instanceof ResourceCacheKey
    String tierKey = this.extractCacheTierFromKey(key);
    DiskCache cache = ExtraDiskCacheAdapter.tiers.get(tierKey);
    if (cache == null)
      throw new Error("Image cache tor tier '" + tierKey + "' wasn't initialized");
    return cache;
  }

  @NonNull
  private String extractCacheTierFromKey(Key key) {
    String str = key.toString();
    Matcher sourceMatcher = SOURCE_PATTERN.matcher(str);
    if (sourceMatcher.find()) {
      String source = sourceMatcher.group(1);
      if (source == null || Objects.equals(source, ""))
        return DEFAULT_TIER_NAME;
      Matcher tierMatcher = SOURCE_CACHE_TIER_PATTERN.matcher(source);
      String tier = tierMatcher.find() ? tierMatcher.group(1) : DEFAULT_TIER_NAME;
      return tier == null ? DEFAULT_TIER_NAME : tier;
    }
    return DEFAULT_TIER_NAME;
  }

  public static void init(Context context, Map<String, Integer> tiers) {
    tiers.forEach((tier, size) -> {
      if (!tier.equals("")) {
        InternalCacheDiskCacheFactory factory =
          new InternalCacheDiskCacheFactory(context, tier, size);
        ExtraDiskCacheAdapter.tiers.put(tier, factory.build());
      }
    });
  }

  /**
   * Default factory for {@link com.dylanvann.fastimage.ExtraDiskCacheAdapter}.
   */
  public static final class Factory implements DiskCache.Factory {
    @Override
    public DiskCache build() {
      return new ExtraDiskCacheAdapter();
    }
  }
}
