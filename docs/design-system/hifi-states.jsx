// Empty / error / loading states — mobile frames at HF.W × HF.H
// Reuses HFFrame, HFIcon, HFArt, HFSlider from hifi-primitives.jsx
// Reuses V3IconBtn, V3CardRoom, V3StackRow, V3BottomStrip from hifi-unified.jsx

// ============================================================
// STATE 1: First run — no speakers found
// ============================================================
const V3StateFirstRun = () => {
  const T = hfTokens();
  return (
    <HFFrame>
      <div style={{flex:1, padding:'32px 28px', display:'flex', flexDirection:'column',
        alignItems:'center', justifyContent:'center', textAlign:'center', gap: 20}}>
        <div style={{
          width: 88, height: 88, borderRadius: 22,
          background: T.fillStrong, display:'flex', alignItems:'center', justifyContent:'center',
        }}>
          <HFIcon name="speakers" size={42} color={T.inkMute} strokeWidth={1.4}/>
        </div>
        <div>
          <div style={{fontSize: 22, fontWeight: 700, letterSpacing:'-0.02em'}}>No speakers yet</div>
          <div style={{fontSize: 13.5, color: T.inkMute, marginTop: 8, lineHeight: 1.5, maxWidth: 260}}>
            Make sure your Sonos system is on the same Wi-Fi network as this device, then start a discovery scan.
          </div>
        </div>
        <div style={{display:'flex', flexDirection:'column', gap: 10, width:'100%', maxWidth: 280, marginTop: 6}}>
          <button style={{
            padding:'12px 16px', borderRadius: 12, background: T.accent, border:'none',
            color: T.onAccent, fontSize: 14, fontWeight: 700, cursor:'pointer',
            display:'inline-flex', alignItems:'center', justifyContent:'center', gap: 8,
          }}>
            <HFIcon name="search" size={15} color={T.onAccent} strokeWidth={2.2}/>
            Scan network
          </button>
          <button style={{
            padding:'12px 16px', borderRadius: 12, background:'transparent', border:`1px solid ${T.line}`,
            color: T.ink2, fontSize: 13.5, fontWeight: 600, cursor:'pointer',
          }}>
            Add by IP address…
          </button>
        </div>
        <div style={{marginTop: 18, fontSize: 11.5, color: T.inkMute, maxWidth: 280, lineHeight: 1.5}}>
          Discovery uses mDNS/SSDP on your local network. No cloud account needed.
        </div>
      </div>
    </HFFrame>
  );
};

// ============================================================
// STATE 2: Discovering — loading with skeleton rooms
// ============================================================
const V3StateDiscovering = () => {
  const T = hfTokens();
  const sk = (w) => (
    <div style={{
      height: 10, width: w, borderRadius: 5,
      background: `linear-gradient(90deg, ${T.fill} 0%, ${T.fillStrong} 50%, ${T.fill} 100%)`,
      backgroundSize: '200% 100%',
      animation: 'hfShimmer 1.4s ease-in-out infinite',
    }}/>
  );
  return (
    <HFFrame>
      <style>{`@keyframes hfShimmer { 0%{background-position:200% 0} 100%{background-position:-200% 0} } @keyframes hfPulse { 0%,100%{opacity:.4} 50%{opacity:1} }`}</style>
      <V3HomeHeader controlsDisabled status={
        <div style={{display:'inline-flex', alignItems:'center', gap: 6}}>
          <span style={{
            width: 8, height: 8, borderRadius:'50%', background: T.accent,
            animation:'hfPulse 1.2s ease-in-out infinite',
          }}/>
          <span style={{fontSize: 12.5, color: T.inkMute}}>Scanning your network…</span>
        </div>
      }/>
      <div style={{flex:1, padding:'0 12px', display:'flex', flexDirection:'column', gap: 8}}>
        {[0,1,2,3].map(i => (
          <div key={i} style={{
            padding:'14px 14px', borderRadius: 14,
            background: T.surface, border:`1px solid ${T.line}`,
            display:'flex', alignItems:'center', gap: 14,
          }}>
            <div style={{
              width: 36, height: 36, borderRadius: 8, background: T.fill,
            }}/>
            <div style={{flex:1, display:'flex', flexDirection:'column', gap: 6}}>
              {sk(110 + i*18)}
              {sk(60 + i*12)}
            </div>
          </div>
        ))}
      </div>
      <div style={{padding:'16px 24px 24px', textAlign:'center'}}>
        <div style={{fontSize: 11.5, color: T.inkMute}}>Found 2 of ~6 expected · Listening for SSDP…</div>
      </div>
    </HFFrame>
  );
};

// ============================================================
// STATE 3: Network lost — banner + greyed system
// ============================================================
const V3StateOffline = () => {
  const T = hfTokens();
  return (
    <HFFrame>
      <div style={{
        margin:'4px 12px 0', padding:'10px 12px', borderRadius: 12,
        background: window.__hfTheme?.dark ? 'rgba(224,138,122,0.10)' : 'rgba(179,74,58,0.08)',
        border: `1px solid ${T.danger}`,
        display:'flex', alignItems:'center', gap: 10,
      }}>
        <div style={{
          width: 26, height: 26, borderRadius:'50%',
          background: T.danger, color:'#fff', flexShrink: 0,
          display:'flex', alignItems:'center', justifyContent:'center',
          fontSize: 14, fontWeight: 700,
        }}>!</div>
        <div style={{flex:1, minWidth:0}}>
          <div style={{fontSize: 12.5, fontWeight: 700, color: T.danger}}>Lost connection to system</div>
          <div style={{fontSize: 11, color: T.ink2, marginTop: 1}}>Last seen 32s ago · Showing cached state</div>
        </div>
        <button style={{
          padding:'5px 10px', borderRadius: 8, background:'transparent',
          border:`1px solid ${T.danger}`, color: T.danger,
          fontSize: 11, fontWeight: 700, cursor:'pointer',
        }}>Retry</button>
      </div>
      <V3HomeHeader subtitle="6 rooms · controls disabled" controlsDisabled/>
      <div style={{flex:1, padding:'0 12px', display:'flex', flexDirection:'column', opacity: 0.55, pointerEvents:'none'}}>
        {V3_ROOMS.slice(0,5).map((r, i) => <V3StackRow key={i} room={r}/>)}
      </div>
    </HFFrame>
  );
};

// ============================================================
// STATE 4: Single speaker offline — inline within Home
// ============================================================
const V3StateRoomOffline = () => {
  const T = hfTokens();
  const rooms = [
    ...V3_ROOMS.slice(0,2),
    { name:'Bedroom', icon:'speaker', devices:'Era 100', vol:0, offline:true },
    ...V3_ROOMS.slice(3),
  ];
  return (
    <HFFrame>
      <V3HomeHeader subtitle="6 rooms · 3 playing · 1 offline"/>
      <div style={{flex:1, padding:'0 12px', display:'flex', flexDirection:'column'}}>
        {rooms.map((r, i) => r.offline ? (
          <div key={i} style={{
            padding:'12px 12px', display:'flex', alignItems:'center', gap: 12,
            borderBottom:`1px solid ${T.line}`, opacity: 0.55,
          }}>
            <HFIcon name={r.icon} size={18} color={T.inkMute}/>
            <div style={{flex:1, minWidth:0}}>
              <div style={{display:'flex', alignItems:'center', gap: 8}}>
                <span style={{fontSize: 14.5, fontWeight: 600, color: T.inkMute}}>{r.name}</span>
                <span style={{
                  fontSize: 9.5, fontWeight: 700, letterSpacing:'.06em',
                  padding:'2px 6px', borderRadius: 4,
                  background: T.fillStrong, color: T.danger,
                }}>OFFLINE</span>
              </div>
              <span style={{fontSize: 11, color: T.inkMute, marginTop: 1, display:'block'}}>
                Not responding · Last seen 4 min ago
              </span>
            </div>
            <button style={{
              padding:'5px 10px', borderRadius: 8, background:'transparent',
              border:`1px solid ${T.line}`, color: T.ink2,
              fontSize: 10.5, fontWeight: 600, cursor:'pointer',
            }}>Retry</button>
          </div>
        ) : <V3StackRow key={i} room={r}/>)}
      </div>
      <V3BottomStrip sources={sourcesFromRooms(rooms)}/>
    </HFFrame>
  );
};

// ============================================================
// STATE 5: Nothing playing — quiet home, no bottom strip
// ============================================================
const V3StateNothingPlaying = () => {
  const T = hfTokens();
  const quietRooms = V3_ROOMS.map(r => ({...r, playing:false, song:null, group:null, groupedWith:null}));
  return (
    <HFFrame>
      <V3HomeHeader subtitle="6 rooms · all quiet"/>
      <div style={{flex:1, padding:'0 12px', display:'flex', flexDirection:'column'}}>
        {quietRooms.map((r, i) => <V3StackRow key={i} room={r}/>)}
      </div>
    </HFFrame>
  );
};

// ============================================================
// STATE 6: Empty queue (in Now Playing)
// ============================================================
const V3StateEmptyQueue = () => {
  const T = hfTokens();
  return (
    <HFFrame>
      <div style={{padding:'4px 18px 12px', display:'flex', alignItems:'center', gap: 12}}>
        <V3IconBtn icon="chevron-down" iconSize={18}/>
        <div style={{flex:1, textAlign:'center'}}>
          <div style={{fontSize: 10.5, fontWeight: 600, letterSpacing:'.08em', textTransform:'uppercase', color: T.inkMute}}>Up next</div>
          <div style={{fontSize: 13, fontWeight: 600, marginTop: 1}}>Living Room</div>
        </div>
        <V3IconBtn icon="kebab" iconSize={17}/>
      </div>
      <div style={{flex:1, padding:'24px', display:'flex', flexDirection:'column',
        alignItems:'center', justifyContent:'center', textAlign:'center', gap: 16}}>
        <div style={{
          width: 72, height: 72, borderRadius: 18,
          background: T.fillStrong, display:'flex', alignItems:'center', justifyContent:'center',
        }}>
          <HFIcon name="queue" size={32} color={T.inkMute} strokeWidth={1.5}/>
        </div>
        <div>
          <div style={{fontSize: 18, fontWeight: 700, letterSpacing:'-0.015em'}}>Queue is empty</div>
          <div style={{fontSize: 13, color: T.inkMute, marginTop: 6, lineHeight: 1.5, maxWidth: 260}}>
            Pick something in Spotify, Apple Music, or any AirPlay source to start a queue here.
          </div>
        </div>
      </div>
    </HFFrame>
  );
};

Object.assign(window, {
  V3StateFirstRun, V3StateDiscovering, V3StateOffline,
  V3StateRoomOffline, V3StateNothingPlaying, V3StateEmptyQueue,
});
