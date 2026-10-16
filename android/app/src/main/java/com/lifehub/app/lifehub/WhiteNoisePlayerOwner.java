package com.lifehub.app.lifehub;

public final class WhiteNoisePlayerOwner {
    public interface Player {
        void prepare(String asset, double volume) throws Exception;
        void start();
        void pause();
        void release();
        boolean isPlaying();
        void setVolume(double volume);
    }

    public interface Factory {
        Player create();
    }

    private final Factory factory;
    private Player player;

    public WhiteNoisePlayerOwner(Factory factory) {
        this.factory = factory;
    }

    public void play(String asset, double volume) throws Exception {
        stop();
        Player candidate = factory.create();
        try {
            candidate.prepare(asset, volume);
            candidate.start();
            player = candidate;
        } catch (Exception failure) {
            try {
                candidate.release();
            } catch (RuntimeException cleanupFailure) {
                failure.addSuppressed(cleanupFailure);
            }
            throw failure;
        }
    }

    public void pause() {
        if (player != null && player.isPlaying()) player.pause();
    }

    public void resume() {
        if (player != null) player.start();
    }

    public void stop() {
        Player previous = player;
        player = null;
        if (previous != null) previous.release();
    }

    public boolean isPlaying() {
        return player != null && player.isPlaying();
    }

    public void setVolume(double volume) {
        if (player != null) player.setVolume(volume);
    }
}
