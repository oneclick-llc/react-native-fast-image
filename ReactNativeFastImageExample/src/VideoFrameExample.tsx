import React, {useState} from 'react';
import {PixelRatio, StyleSheet, Text, View} from 'react-native';
import FastImage from 'react-native-fast-image';
import Section from './Section';
import SectionFlex from './SectionFlex';
import FeatureText from './FeatureText';
import BulletText from './BulletText';
import Button from './Button';
import {useCacheBust} from './useCacheBust';

/**
 * Кадр из видео — обычной картинкой.
 *
 * Ссылка ведёт на mp4, а в FastImage она передаётся так же, как любая другая:
 * ни хука, ни файла на диске, ни состояния в JS. Кадр достаёт нативный
 * загрузчик (AVFoundation на iOS), читая заголовок контейнера и нужные сэмплы,
 * а не файл целиком.
 *
 * Ролик выбран большой намеренно: 30 МБ. Если кадр появился за секунду,
 * значит скачался далеко не весь. Отдаётся с поддержкой Range (206) — без неё
 * системе пришлось бы тянуть файл целиком, и вся затея теряет смысл.
 */
const VIDEO_URL =
  'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_30MB.mp4';

const TILE = 140;
const DECODE = {
  width: PixelRatio.getPixelSizeForLayoutSize(TILE),
  height: PixelRatio.getPixelSizeForLayoutSize(TILE),
};

interface TileProps {
  url: string;
  label: string;
  isVideo?: boolean;
}

const Tile = ({url, label, isVideo}: TileProps) => {
  const [state, setState] = useState('…');
  const [startedAt] = useState(() => Date.now());

  return (
    <View style={styles.tile}>
      <FastImage
        style={styles.image}
        source={{uri: url, isVideo}}
        resizeSize={DECODE}
        onLoad={e =>
          setState(
            `${e.nativeEvent.width}×${e.nativeEvent.height}, ${
              Date.now() - startedAt
            } мс`,
          )
        }
        onError={() => setState('не получилось')}
      />
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.value}>{state}</Text>
    </View>
  );
};

export const VideoFrameExample = () => {
  const {url, bust} = useCacheBust(VIDEO_URL);

  return (
    <View>
      <Section>
        <FeatureText text="• Кадр из видео вместо картинки." />
        <BulletText text="Ссылка ведёт на mp4 размером 30 МБ. Кадр приходит за секунду — файл целиком не качается." />
        <BulletText text="Слева вид определяется по расширению, справа — признаком isVideo у источника." />
      </Section>
      <SectionFlex style={styles.section}>
        <Tile url={url} label="по расширению" />
        <Tile url={url} label="source.isVideo" isVideo />
      </SectionFlex>
      <SectionFlex style={styles.buttons}>
        <Button text="Bust" onPress={bust} />
      </SectionFlex>
    </View>
  );
};

const styles = StyleSheet.create({
  section: {
    justifyContent: 'space-around',
    paddingVertical: 10,
  },
  buttons: {
    justifyContent: 'center',
    paddingBottom: 10,
  },
  tile: {
    alignItems: 'center',
  },
  image: {
    width: TILE,
    height: TILE,
    backgroundColor: '#ddd',
  },
  label: {
    marginTop: 6,
    fontSize: 11,
    color: '#666',
  },
  value: {
    fontSize: 13,
    fontWeight: '700',
    color: '#222',
  },
});
