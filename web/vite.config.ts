import { defineConfig } from 'vite'
import preact from '@preact/preset-vite'
import { viteSingleFile } from 'vite-plugin-singlefile'
import { compression } from 'vite-plugin-compression2'

export default defineConfig({
  plugins: [
    preact(),
    viteSingleFile(),
    compression({
      algorithms: ["gzip"],
    }),
    compression({
      algorithms: ["br"],
    })
  ],
  resolve: {
    alias: {
      'react': 'preact/compat',
      'react-dom/test-utils': 'preact/compat',
      'react-dom': 'preact/compat',
      'react/jsx-runtime': 'preact/jsx-runtime'
    }
  },
  build: {
    target: 'esnext',
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true,
        passes: 2,
      },
      format: {
        comments: false,
      }
    },
    assetsInlineLimit: 100000000,
  }
})