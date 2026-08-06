package com.dylanvann.fastimage;

import android.graphics.Bitmap;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.bumptech.glide.Priority;
import com.bumptech.glide.load.DataSource;
import com.bumptech.glide.load.Options;
import com.bumptech.glide.load.data.DataFetcher;
import com.bumptech.glide.load.model.GlideUrl;
import com.bumptech.glide.load.model.ModelLoader;
import com.bumptech.glide.load.model.ModelLoaderFactory;
import com.bumptech.glide.load.model.MultiModelLoaderFactory;
import com.bumptech.glide.signature.ObjectKey;

import java.io.IOException;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/**
 * Кадр из видео по ссылке — обычной картинкой и без скачивания ролика.
 *
 * `MediaMetadataRetriever.setDataSource(url, headers)` читает удалённый файл
 * ДИАПАЗОНАМИ: заголовок контейнера, потом сэмплы вокруг нужного времени.
 * Glide так не умеет сам: его `VideoDecoder` берёт кадр только из локального
 * файла (ему нужен FileDescriptor), а для ссылки сначала скачал бы файл
 * целиком — то есть мегабайты ради одной картинки.
 *
 * Дальше кадр живёт как любая другая картинка Glide: его кэш, его отмена, его
 * склейка одинаковых запросов — список, рисующий одну плитку много раз, сам
 * попадёт в один запрос.
 */
public class FastImageVideoFrameLoader implements ModelLoader<GlideUrl, Bitmap> {

    /**
     * Расширения, которые читает системный извлекатель кадров.
     *
     * webm и mkv сюда не входят намеренно: не на всех прошивках открываются, и
     * лучше честно не взяться за ссылку, чем отдать пустую плитку после
     * запроса.
     */
    private static final Set<String> VIDEO_EXTENSIONS = new HashSet<>(Arrays.asList(
            "mp4", "m4v", "mov", "qt", "3gp", "3g2"
    ));

    public static boolean isVideoUrl(GlideUrl model) {
        String url = model.toStringUrl();
        if (FastImageVideoUrl.isKnown(url)) {
            return true;
        }
        String path = Uri.parse(url).getPath();
        if (path == null) {
            return false;
        }
        int dot = path.lastIndexOf('.');
        if (dot < 0 || dot == path.length() - 1) {
            return false;
        }
        return VIDEO_EXTENSIONS.contains(path.substring(dot + 1).toLowerCase(Locale.US));
    }

    @Nullable
    @Override
    public LoadData<Bitmap> buildLoadData(@NonNull GlideUrl model, int width, int height, @NonNull Options options) {
        // В ключ входит размер: кадр распаковывается сразу в него, значит для
        // другой плитки это другая картинка. Сам размер приходит от Glide —
        // тот, что посчитан по вью или задан `override()`, то есть тем же
        // `resizeSize`, что и у картинок.
        ObjectKey key = new ObjectKey(model.getCacheKey() + "|" + width + "x" + height);
        return new LoadData<>(key, new FrameFetcher(model, width, height));
    }

    @Override
    public boolean handles(@NonNull GlideUrl model) {
        return isVideoUrl(model);
    }

    public static class Factory implements ModelLoaderFactory<GlideUrl, Bitmap> {
        @NonNull
        @Override
        public ModelLoader<GlideUrl, Bitmap> build(@NonNull MultiModelLoaderFactory multiFactory) {
            return new FastImageVideoFrameLoader();
        }

        @Override
        public void teardown() {
        }
    }

    private static class FrameFetcher implements DataFetcher<Bitmap> {
        private final GlideUrl model;
        private final int width;
        private final int height;
        private volatile boolean cancelled;

        FrameFetcher(GlideUrl model, int width, int height) {
            this.model = model;
            this.width = width;
            this.height = height;
        }

        @Override
        public void loadData(@NonNull Priority priority, @NonNull DataCallback<? super Bitmap> callback) {
            MediaMetadataRetriever retriever = new MediaMetadataRetriever();
            try {
                String url = model.toStringUrl();
                if (url.startsWith("file://") || url.startsWith("/")) {
                    retriever.setDataSource(url.replaceFirst("^file://", ""));
                } else {
                    retriever.setDataSource(url, model.getHeaders());
                }

                // OPTION_CLOSEST_SYNC — ближайший КЛЮЧЕВОЙ кадр. Точный
                // заставил бы декодировать всё от предыдущего ключевого:
                // качать больше, считать дольше, а для превью разницы не
                // видно.
                Bitmap frame;
                boolean hasSize = width > 0 && height > 0;
                if (hasSize && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    // Распаковка сразу в размер плитки: 4K-кадр в сотню точек —
                    // это мегабайты памяти на ровном месте.
                    frame = retriever.getScaledFrameAtTime(
                            0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, width, height);
                } else {
                    frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
                }

                if (cancelled) {
                    if (frame != null) {
                        frame.recycle();
                    }
                    return;
                }
                if (frame == null) {
                    callback.onLoadFailed(new IOException("No frame in " + url));
                    return;
                }
                callback.onDataReady(frame);
            } catch (Throwable error) {
                if (!cancelled) {
                    callback.onLoadFailed(error instanceof Exception
                            ? (Exception) error
                            : new IOException(error));
                }
            } finally {
                try {
                    retriever.release();
                } catch (Throwable ignored) {
                    // release() швыряется на некоторых прошивках — кадр это уже
                    // не отменяет.
                }
            }
        }

        @Override
        public void cleanup() {
            // Битмап уходит в Glide, и дальше его судьба — за пулом Glide.
        }

        @Override
        public void cancel() {
            // Прервать чтение системный извлекатель не даёт: release() из
            // чужого потока во время getFrameAtTime роняет процесс. Поэтому
            // работа доигрывается, а результат выбрасывается.
            cancelled = true;
        }

        @NonNull
        @Override
        public Class<Bitmap> getDataClass() {
            return Bitmap.class;
        }

        @NonNull
        @Override
        public DataSource getDataSource() {
            return DataSource.REMOTE;
        }
    }
}
