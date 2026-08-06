package com.dylanvann.fastimage;

import androidx.annotation.NonNull;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Ссылки, про которые известно, что они ведут на видео.
 *
 * Нужно там, где по самой ссылке этого не видно: CDN часто отдаёт файлы без
 * расширения вовсе, а вид содержимого знает только вызывающий — он получил его
 * от сервера вместе с mime и присылает признаком `source.isVideo`.
 *
 * Почему список, а не свой класс модели. Сначала здесь был `GlideUrl`-наследник
 * с пометкой — и он ломал склейку одинаковых запросов: две плитки с ОДНОЙ
 * ссылкой, одна с признаком и одна без, читали ролик дважды (замерено: два
 * запроса по 3.67 МБ вместо одного). Модель участвует в ключе запроса, поэтому
 * пометка не должна её менять — иначе одна и та же картинка расходится на две.
 */
final class FastImageVideoUrl {

    /**
     * Ограниченный размер: это подсказка, а не кэш. Забыть старую ссылку
     * не страшно — к тому времени плитка давно уехала с экрана.
     */
    private static final int LIMIT = 512;

    private static final Map<String, Boolean> known =
            new LinkedHashMap<String, Boolean>(64, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<String, Boolean> eldest) {
                    return size() > LIMIT;
                }
            };

    private FastImageVideoUrl() {
    }

    static void remember(@NonNull String url) {
        synchronized (known) {
            known.put(url, Boolean.TRUE);
        }
    }

    static boolean isKnown(@NonNull String url) {
        synchronized (known) {
            return known.containsKey(url);
        }
    }
}
