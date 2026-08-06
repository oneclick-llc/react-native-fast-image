const {getDefaultConfig, mergeConfig} = require('@react-native/metro-config');
const path = require('path');

const pak = require('../package.json');

/** Путь в кусок регулярки: на macOS в нём нет спецсимволов, но точка есть. */
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const root = path.resolve(__dirname, '..');
// Только peer-зависимости: react и react-native должны попасть в бандл ровно
// одной копией — той, что лежит в node_modules примера. Копия из корня пакета
// даёт «Invalid hook call» и два реестра нативных компонентов.
const modules = Object.keys({...pak.peerDependencies});

/**
 * Metro читает исходники пакета напрямую (`main` смотрит в src/index), поэтому
 * правка в ../src подхватывается обычным reload — ни сборки пакета, ни
 * переустановки.
 *
 * @type {import('metro-config').MetroConfig}
 */
const config = {
  watchFolders: [root],

  resolver: {
    blockList: modules.map(
      m => new RegExp(`^${escape(path.join(root, 'node_modules', m))}\\/.*$`),
    ),

    extraNodeModules: modules.reduce((acc, name) => {
      acc[name] = path.join(__dirname, 'node_modules', name);
      return acc;
    }, {}),
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
