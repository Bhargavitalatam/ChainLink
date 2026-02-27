import { defineConfig } from 'vite'

export default defineConfig({
    base: './', // Ensures assets are correctly linked when deployed to GitHub Pages
    build: {
        outDir: 'dist',
    }
})
