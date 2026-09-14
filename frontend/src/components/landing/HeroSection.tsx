/**
 * HeroSection — public landing hero.
 *
 * Uses the real asset served from Vite's public directory (`/hero-section.mp4`).
 * If that file cannot be played (missing, unsupported, blocked) the layout
 * falls back to a designed panel — the copy never depends on the video, and no
 * replacement footage or fake screenshot is generated.
 */
import { useEffect, useRef, useState } from 'react';
import { Button } from '../ui/Button';
import { Icon } from '../ui/Icon';
import { navigate } from '../../router';

const HERO_VIDEO_SRC = '/hero-section.mp4';

type VideoState = 'loading' | 'ready' | 'failed';

export function HeroSection() {
  const [videoState, setVideoState] = useState<VideoState>('loading');
  // Tracks whether this element ever decoded a frame, so a spurious media event
  // (e.g. an aborted load on re-render) cannot mask a video that does play.
  const loadedRef = useRef(false);

  // Ask the server whether the asset exists. A missing /hero-section.mp4 must
  // always resolve to the designed fallback, without relying on media events.
  useEffect(() => {
    let alive = true;
    fetch(HERO_VIDEO_SRC, { method: 'HEAD' })
      .then((res) => {
        if (!alive) return;
        if (!res.ok) setVideoState('failed');
        else setVideoState((prev) => (prev === 'failed' ? prev : 'ready'));
      })
      .catch(() => {
        if (alive) setVideoState('failed');
      });
    return () => {
      alive = false;
    };
  }, []);

  return (
    <section className="l-hero l-anchor" id="top" aria-labelledby="hero-title">
      <div className="l-container">
        <div className="l-hero__grid">
          <div className="l-hero__text">
            <span className="l-hero__badge">
              <Icon name="shieldCheck" size={16} />
              AI-assisted screening · human-in-the-loop
            </span>

            <h1 className="l-hero__title" id="hero-title">
              Smarter retinal screening.
              <br />
              <em>Human decisions remain in control.</em>
            </h1>

            <p className="l-hero__lead">
              RetinaSense is decision-support for diabetic retinopathy screening.
              It assesses fundus image quality, produces an AI-assisted DR grade,
              and keeps the clinician&apos;s review as the separate, final
              decision — so the original AI output is never overwritten.
            </p>

            <div className="l-hero__actions">
              <Button variant="primary" size="lg" icon="plus" onClick={() => navigate('/screening')}>
                Start screening
              </Button>
              <Button variant="secondary" size="lg" icon="grid" onClick={() => navigate('/dashboard')}>
                Open dashboard
              </Button>
            </div>

            <div className="l-hero__trust">
              <Icon name="info" size={17} />
              <span>
                Screening decision-support only. RetinaSense does not diagnose, and
                when the backend or model is unavailable no result is shown in its place.
              </span>
            </div>
          </div>

          <div className="l-hero__media">
            {videoState === 'failed' ? (
              <div className="l-hero__fallback" role="img" aria-label="RetinaSense screening workflow illustration">
                <span className="l-hero__fallback-icon" aria-hidden="true">
                  <Icon name="eye" size={26} />
                </span>
                <p className="l-hero__fallback-title">Retinal screening, end to end</p>
                <p className="note-text">
                  Quality gate → AI-assisted grading → human review → final decision.
                </p>
              </div>
            ) : (
              <video
                className="l-hero__video"
                autoPlay
                muted
                loop
                playsInline
                preload="metadata"
                aria-label="RetinaSense screening workflow animation"
                onLoadedData={() => {
                  loadedRef.current = true;
                }}
                onError={() => {
                  // Only a failure before any frame decoded means "cannot play".
                  if (!loadedRef.current) setVideoState('failed');
                }}
              >
                <source src={HERO_VIDEO_SRC} type="video/mp4" />
              </video>
            )}

            <p className="l-hero__caption">
              <Icon name="scan" size={15} />
              Quality gate → AI grade → human review → final decision
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
