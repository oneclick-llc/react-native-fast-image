import React, {useState} from 'react';
import {StyleSheet, View} from 'react-native';
import SectionFlex from './SectionFlex';
import FastImage from 'react-native-fast-image';
import Section from './Section';
import FeatureText from './FeatureText';
import Button from './Button';
import {useCacheBust} from './useCacheBust';

const IMAGE_URL =
  'https://cdn-images-1.medium.com/max/1600/1*-CY5bU4OqiJRox7G00sftw.gif';

export const PreloadExample = () => {
  const [show, setShow] = useState(false);
  const [progress, setProgress] = useState<number>();
  const {url, bust} = useCacheBust(IMAGE_URL);

  const preload = () => {
    FastImage.preload([{uri: url}]);
  };

  return (
    <View>
      <Section>
        <FeatureText text="• Preloading." />
        <FeatureText text="• Progress from the onProgress callback." />
      </Section>
      <SectionFlex style={styles.section}>
        {show ? (
          <FastImage
            style={styles.image}
            source={{uri: url}}
            onProgress={e =>
              setProgress(
                e.nativeEvent.total > 0
                  ? e.nativeEvent.loaded / e.nativeEvent.total
                  : undefined,
              )
            }
            onLoad={() => setProgress(1)}
          />
        ) : (
          <View style={styles.image} />
        )}
        <View style={styles.progressTrack}>
          <View
            style={[styles.progressFill, {flex: progress ?? 0}]}
          />
          <View style={{flex: 1 - (progress ?? 0)}} />
        </View>
        <View style={styles.buttons}>
          <View style={styles.buttonView}>
            <Button text="Bust" onPress={bust} />
          </View>
          <View style={styles.buttonView}>
            <Button text="Preload" onPress={preload} />
          </View>
          <View style={styles.buttonView}>
            <Button
              text={show ? 'Hide' : 'Show'}
              onPress={() => setShow(v => !v)}
            />
          </View>
        </View>
      </SectionFlex>
    </View>
  );
};

const styles = StyleSheet.create({
  buttonView: {flex: 1},
  section: {
    flexDirection: 'column',
    alignItems: 'center',
  },
  buttons: {
    flexDirection: 'row',
    marginHorizontal: 20,
    marginBottom: 10,
  },
  image: {
    backgroundColor: '#ddd',
    margin: 20,
    marginBottom: 10,
    height: 100,
    width: 100,
  },
  progressTrack: {
    flexDirection: 'row',
    height: 4,
    width: 160,
    marginBottom: 10,
    backgroundColor: '#ddd',
  },
  progressFill: {
    backgroundColor: '#4c9eff',
  },
});
