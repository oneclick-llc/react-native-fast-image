import { NativeModules } from 'react-native'

const nativeGetCachedFile = jest.fn()

// The module object is captured when `./index` is evaluated, so the mock has to
// be in place before the require below.
NativeModules.FastImageViewModule = {
    preload: jest.fn(),
    clearMemoryCache: jest.fn(),
    clearDiskCache: jest.fn(),
    getCachedFile: nativeGetCachedFile,
}

const FastImage = require('./index').default

describe('FastImage.getCachedFile', () => {
    beforeEach(() => {
        nativeGetCachedFile.mockReset()
    })

    it('hands the source to the native module unchanged', async () => {
        nativeGetCachedFile.mockResolvedValue('/cache/primary/abc.jpg')
        const source = {
            uri: 'https://example.com/photo.jpg',
            headers: { token: 'someToken' },
            cacheTier: FastImage.cacheTier.secondary,
        }

        await FastImage.getCachedFile(source)

        expect(nativeGetCachedFile).toHaveBeenCalledTimes(1)
        expect(nativeGetCachedFile).toHaveBeenCalledWith(source)
    })

    it('resolves with the path the native module resolves', async () => {
        nativeGetCachedFile.mockResolvedValue('/cache/primary/abc.jpg')

        await expect(
            FastImage.getCachedFile({ uri: 'https://example.com/photo.jpg' }),
        ).resolves.toBe('/cache/primary/abc.jpg')
    })

    it('rejects with the native rejection', async () => {
        const failure = Object.assign(new Error('load failed'), {
            code: 'E_LOAD_FAILED',
        })
        nativeGetCachedFile.mockRejectedValue(failure)

        await expect(
            FastImage.getCachedFile({ uri: 'https://example.com/missing.jpg' }),
        ).rejects.toBe(failure)
    })

    it('sits beside the other static cache methods', () => {
        expect(typeof FastImage.getCachedFile).toBe('function')
        expect(typeof FastImage.preload).toBe('function')
        expect(typeof FastImage.clearDiskCache).toBe('function')
    })
})
