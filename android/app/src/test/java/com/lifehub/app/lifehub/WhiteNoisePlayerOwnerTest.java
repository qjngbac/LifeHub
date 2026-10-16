package com.lifehub.app.lifehub;

import java.io.IOException;
import java.util.ArrayDeque;
import org.junit.Test;
import static org.junit.Assert.*;

public class WhiteNoisePlayerOwnerTest {
    @Test
    public void preparationFailureReleasesPlayerAndAllowsRetry() throws Exception {
        FakePlayer failed = new FakePlayer();
        failed.failPrepare = true;
        FakePlayer retry = new FakePlayer();
        WhiteNoisePlayerOwner owner = owner(failed, retry);

        assertThrows(IOException.class, () -> owner.play("missing.wav", 0.5));
        assertEquals(1, failed.releases);
        assertFalse(owner.isPlaying());
        owner.play("rain.wav", 0.5);
        assertTrue(owner.isPlaying());
        assertEquals("rain.wav", retry.asset);
    }

    @Test
    public void startFailureReleasesPlayerAndAllowsRetry() throws Exception {
        FakePlayer failed = new FakePlayer();
        failed.failStart = true;
        FakePlayer retry = new FakePlayer();
        WhiteNoisePlayerOwner owner = owner(failed, retry);

        assertThrows(IllegalStateException.class, () -> owner.play("rain.wav", 0.5));
        assertEquals(1, failed.releases);
        assertFalse(owner.isPlaying());
        owner.play("waves.wav", 0.5);
        assertTrue(owner.isPlaying());
    }

    @Test
    public void replacingAndStoppingReleaseEachPlayerOnce() throws Exception {
        FakePlayer first = new FakePlayer();
        FakePlayer second = new FakePlayer();
        WhiteNoisePlayerOwner owner = owner(first, second);
        owner.play("rain.wav", 0.3);
        owner.pause();
        assertFalse(owner.isPlaying());
        owner.resume();
        assertTrue(owner.isPlaying());
        owner.setVolume(0.7);
        assertEquals(0.7, first.volume, 0.0);
        owner.play("waves.wav", 0.4);
        assertEquals(1, first.releases);
        owner.stop();
        owner.stop();
        assertEquals(1, second.releases);
        assertFalse(owner.isPlaying());
    }

    private WhiteNoisePlayerOwner owner(FakePlayer... players) {
        ArrayDeque<FakePlayer> queue = new ArrayDeque<>();
        for (FakePlayer player : players) queue.add(player);
        return new WhiteNoisePlayerOwner(queue::remove);
    }

    private static final class FakePlayer implements WhiteNoisePlayerOwner.Player {
        boolean failPrepare;
        boolean failStart;
        boolean prepared;
        boolean playing;
        int releases;
        String asset;
        double volume;

        public void prepare(String asset, double volume) throws IOException {
            if (failPrepare) throw new IOException("prepare failed");
            this.asset = asset;
            this.volume = volume;
            prepared = true;
        }
        public void start() {
            if (!prepared || failStart) throw new IllegalStateException("start failed");
            playing = true;
        }
        public void pause() { playing = false; }
        public void release() { releases++; playing = false; }
        public boolean isPlaying() {
            if (!prepared) throw new IllegalStateException("query before prepare");
            return playing;
        }
        public void setVolume(double volume) { this.volume = volume; }
    }
}
