import React from 'react';
import {Platform, StatusBar, StyleSheet, View} from 'react-native';

/**
 * Высота статус-бара без отдельной библиотеки.
 *
 * На Android её отдаёт сам StatusBar, на iOS её нет вовсе — берём 44 (вырез
 * есть у всех живых устройств). Точность здесь не нужна: это подложка, чтобы
 * содержимое не просвечивало сквозь статус-бар.
 */
export const STATUS_BAR_HEIGHT =
  Platform.OS === 'android' ? StatusBar.currentHeight ?? 24 : 44;

export default () => <View style={styles.statusBarUnderlay} />;

const styles = StyleSheet.create({
  statusBarUnderlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: STATUS_BAR_HEIGHT,
    backgroundColor: 'white',
  },
});
