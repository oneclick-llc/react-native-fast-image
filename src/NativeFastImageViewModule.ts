import type { TurboModule } from 'react-native'
import { TurboModuleRegistry } from 'react-native'
import { Source } from './index'

export interface Spec extends TurboModule {
    preload: (sources: Source[]) => void
    clearMemoryCache: () => Promise<void>
    clearDiskCache: () => Promise<void>
    // `Object`, not `Source`: codegen cannot resolve a type imported from another
    // file, and an unresolved type in a parameter position fails the build.
    getCachedFile: (source: Object) => Promise<string>
}

export default TurboModuleRegistry.getEnforcing<Spec>('FastImageViewModule')
