// Unified v3 — one IA, layout toggle on Home, no tab bar
// Reuses hifi-primitives.jsx (HFFrame, HFIcon, HFArt, HFSlider, HFToggle, HFCheck, HFChip, HFCard, HFRow, HFSectionHd, hfTokens, MONO, FONT, HF)

// ---------- shared header pattern ----------
// V3Tap — guarantees a >=44px tappable area around a small glyph,
// keeping the visual icon size intact (transparent hit-slop).
const V3Tap = ({ children, onClick, size = 44, style }) => (
  <button onClick={onClick} style={{
    minWidth: size, minHeight: size, padding: 0, background:'transparent',
    border:'none', cursor:'pointer', display:'inline-flex',
    alignItems:'center', justifyContent:'center', flexShrink: 0, ...style,
  }}>{children}</button>
);

const V3IconBtn = ({ icon, onClick, size = 44, iconSize = 17 }) => {
  const T = hfTokens();
  return (
    <button onClick={onClick} style={{
      width: size, height: size, borderRadius: 10,
      background: 'transparent', border:`1px solid ${T.line}`,
      display:'flex', alignItems:'center', justifyContent:'center',
      color: T.ink2, cursor:'pointer', flexShrink: 0,
    }}>
      <HFIcon name={icon} size={iconSize}/>
    </button>
  );
};

// ---------- Brand mark — Nested Rooms ----------
const OtoMark = ({ size = 28, fg }) => {
  const T = hfTokens();
  const c = fg || T.accent;
  const cx = size/2, cy = size/2;
  const sw = size * 0.07;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{display:'block'}}>
      <rect x={size*0.10} y={size*0.10} width={size*0.80} height={size*0.80}
        rx={size*0.11} fill="none" stroke={c} strokeWidth={sw} opacity={0.28}/>
      <rect x={size*0.24} y={size*0.24} width={size*0.52} height={size*0.52}
        rx={size*0.085} fill="none" stroke={c} strokeWidth={sw} opacity={0.58}/>
      <rect x={cx - size*0.115} y={cy - size*0.115} width={size*0.23} height={size*0.23}
        rx={size*0.05} fill={c}/>
    </svg>
  );
};

// ---------- data ----------
const V3_ROOMS = [
  { name:'Living Room', icon:'soundbar', devices:'Beam · Era 300 ×2 · Sub Mini',
    vol:0.42, song:'Black Star', artist:'Radiohead', art:'noir',
    playing:true, group:['Kitchen'], host:true },
  { name:'Kitchen', icon:'speaker', devices:'One SL',
    vol:0.30, song:'Black Star', artist:'Radiohead', art:'noir',
    playing:true, groupedWith:'Living Room' },
  { name:'Bedroom', icon:'speaker', devices:'Era 100', vol:0.15, playing:false },
  { name:'Office', icon:'speaker', devices:'Move 2',
    vol:0.55, song:'Strobe', artist:'Deadmau5', art:'ink', playing:true },
  { name:'Patio', icon:'speakers', devices:'Roam ×2', vol:0, off:true },
  { name:'Bathroom', icon:'speaker', devices:'One SL', vol:0.25, playing:false },
];

// Derive the active sources from room state — the single source of truth, so a
// Home screen can never claim a different number of sources than its rooms imply.
// A "source" is one independent stream: a GROUP of rooms playing in sync, or a
// single room on its own. Transport is per-source (pausing any member pauses the
// whole source); volume stays per-room. Idle / powered-off rooms aren't sources.
function sourcesFromRooms(rooms){
  const out = [], seen = new Set();
  for (const r of rooms){
    if (!r.playing || r.off || seen.has(r.name)) continue;
    const members = r.group ? [r.name, ...r.group] : [r.name];
    members.forEach(m => seen.add(m));
    out.push({ id:'src-'+r.name, label: members.join(' + '),
      song: r.song, artist: r.artist, art: r.art, rooms: members.length });
  }
  return out;
}

// Single-source scenario (Office idle) — only the Living Room + Kitchen group
// plays, to document the single-row bar against a valid room state.
const V3_ROOMS_SOLO = V3_ROOMS.map(r =>
  r.name === 'Office' ? { ...r, playing:false, song:null, artist:null } : r);

// ---------- layout toggle ----------
const V3LayoutToggle = ({ value, onChange }) => {
  const T = hfTokens();
  const Btn = ({ id, icon }) => {
    const on = value === id;
    return (
      <button onClick={() => onChange && onChange(id)} style={{
        width: 40, height: 36, borderRadius: 7, border:'none',
        background: on ? T.surface : 'transparent',
        boxShadow: on ? '0 1px 3px rgba(0,0,0,0.08)' : 'none',
        display:'flex', alignItems:'center', justifyContent:'center',
        color: on ? T.ink : T.inkMute, cursor:'pointer',
      }}>
        <HFIcon name={icon} size={14} color={on ? T.ink : T.inkMute}/>
      </button>
    );
  };
  return (
    <div style={{
      display:'inline-flex', padding: 4, borderRadius: 9,
      background: T.fillStrong, gap: 2, flexShrink: 0,
    }}>
      <Btn id="cards" icon="grid"/>
      <Btn id="stack" icon="list"/>
    </div>
  );
};

// Add grid + list icons (not in primitives)
const _v3PatchIcons = (() => {
  const orig = window.HFIcon;
  window.HFIcon = ({ name, size = 18, color, strokeWidth }) => {
    const T = hfTokens();
    const c = color || T.ink;
    const sw = strokeWidth || 1.6;
    const p = { width: size, height: size, viewBox:'0 0 24 24', fill:'none',
      stroke: c, strokeWidth: sw, strokeLinecap:'round', strokeLinejoin:'round',
      style:{display:'block', flexShrink:0} };
    if (name === 'grid')  return <svg {...p}><rect x="4" y="4" width="7" height="7" rx="1"/><rect x="13" y="4" width="7" height="7" rx="1"/><rect x="4" y="13" width="7" height="7" rx="1"/><rect x="13" y="13" width="7" height="7" rx="1"/></svg>;
    if (name === 'list')  return <svg {...p}><path d="M3 6 H21 M3 12 H21 M3 18 H21"/></svg>;
    if (name === 'drag')  return <svg {...p}><circle cx="9" cy="6" r="1.3" fill={c} stroke="none"/><circle cx="15" cy="6" r="1.3" fill={c} stroke="none"/><circle cx="9" cy="12" r="1.3" fill={c} stroke="none"/><circle cx="15" cy="12" r="1.3" fill={c} stroke="none"/><circle cx="9" cy="18" r="1.3" fill={c} stroke="none"/><circle cx="15" cy="18" r="1.3" fill={c} stroke="none"/></svg>;
    return orig({ name, size, color, strokeWidth });
  };
})();

// ---------- Home header ----------
// Single source of truth for the Home/Speakers header across the hub AND all
// state screens. `subtitle` sets the status line; pass `status` to render a
// custom node instead (e.g. the scanning pulse). `controlsDisabled` dims the
// playback-related controls (toggle + search) while keeping Settings reachable.
const V3HomeHeader = ({
  layout = 'stack', onLayout, onSettings,
  subtitle = '6 rooms · 3 playing',
  status = null,
  controlsDisabled = false,
  showToggle = true,
}) => {
  const T = hfTokens();
  return (
    <div>
      <div style={{padding:'2px 18px 0', display:'flex', alignItems:'center', gap: 8}}>
        <OtoMark size={18}/>
        <span style={{fontSize: 12.5, fontWeight: 700, letterSpacing:'-0.01em', color: T.ink2}}>oto</span>
      </div>
      <div style={{padding:'6px 18px 14px', display:'flex', alignItems:'flex-end', gap: 10}}>
        <div style={{flex:1, minWidth: 0}}>
          <div style={{fontSize: 26, fontWeight: 700, letterSpacing:'-0.025em', lineHeight: 1.05}}>Speakers</div>
          {status
            ? <div style={{marginTop: 4}}>{status}</div>
            : <div style={{fontSize: 12.5, color: T.inkMute, marginTop: 3}}>{subtitle}</div>}
        </div>
        <div style={{display:'flex', alignItems:'flex-end', gap: 10,
          opacity: controlsDisabled ? 0.4 : 1, pointerEvents: controlsDisabled ? 'none' : 'auto'}}>
          {showToggle && <V3LayoutToggle value={layout} onChange={onLayout}/>}
          <V3IconBtn icon="search"/>
        </div>
        <V3IconBtn icon="settings" onClick={onSettings}/>
      </div>
    </div>
  );
};

// ---------- Cards row ----------
const V3CardRoom = ({ room }) => {
  const T = hfTokens();
  const playing = room.playing && !room.off;
  return (
    <div style={{
      background: T.surface, border:`1px solid ${T.line}`, borderRadius: 16,
      padding: 12, display:'flex', flexDirection:'column', gap: 10,
      opacity: room.off ? 0.55 : 1,
    }}>
      <div style={{display:'flex', alignItems:'center', gap: 8, minWidth:0}}>
        <HFIcon name={room.icon} size={14} color={T.inkMute} strokeWidth={1.6}/>
        <span style={{fontSize: 14, fontWeight: 600, flex:1, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{room.name}</span>
        {(room.group || room.groupedWith) && (
          <span style={{display:'inline-flex', alignItems:'center', gap: 3, fontSize: 10.5, fontWeight: 600,
            padding:'2px 6px', borderRadius: 4, background: T.accentSoft, color: T.accent, flexShrink:0}}>
            <HFIcon name="link" size={10} color={T.accent} strokeWidth={2}/>
            {room.group ? `+${room.group.length}` : 'group'}
          </span>
        )}
      </div>
      {playing ? (
        <div style={{display:'flex', alignItems:'center', gap: 10}}>
          <HFArt variant={room.art} size={44} radius={8}/>
          <div style={{flex:1, minWidth:0}}>
            <div style={{fontSize: 12, fontWeight: 600, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{room.song}</div>
            <div style={{fontSize: 10.5, color: T.inkMute, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{room.artist}</div>
          </div>
          <button style={{
            width: 44, height: 44, borderRadius: 999, background: 'transparent', border:'none', padding: 0,
            display:'flex', alignItems:'center', justifyContent:'center', cursor:'pointer', flexShrink:0,
          }}>
            <span style={{width: 34, height: 34, borderRadius: 999, background: T.ink,
              display:'flex', alignItems:'center', justifyContent:'center'}}>
              <HFIcon name="pause" size={15} color={T.surface}/>
            </span>
          </button>
        </div>
      ) : (
        <div style={{display:'flex', alignItems:'center', gap: 10, minHeight: 44}}>
          <div style={{width: 44, height: 44, borderRadius: 8, background: T.fill,
            display:'flex', alignItems:'center', justifyContent:'center'}}>
            <HFIcon name="play" size={16} color={T.inkFaint}/>
          </div>
          <span style={{fontSize: 11.5, color: T.inkMute, flex:1}}>{room.off ? 'Powered off' : 'Idle'}</span>
        </div>
      )}
      <div style={{display:'flex', alignItems:'center', gap: 8}}>
        <HFIcon name={room.vol < 0.02 ? 'volume-mute' : room.vol < 0.4 ? 'volume-low' : 'volume'} size={12} color={T.inkFaint} strokeWidth={1.5}/>
        <div style={{flex:1}}><HFSlider value={room.vol} h={3} showThumb={false}/></div>
        <span style={{fontSize: 10.5, fontFamily: MONO, color: T.inkMute, width: 18, textAlign:'right', fontVariantNumeric:'tabular-nums'}}>{Math.round(room.vol*100)}</span>
      </div>
    </div>
  );
};

// ---------- Stack row ----------
const V3StackRow = ({ room, expanded }) => {
  const T = hfTokens();
  return (
    <div style={{
      background: expanded ? T.surface : 'transparent',
      border:`1px solid ${expanded ? T.line : 'transparent'}`,
      borderRadius: expanded ? 14 : 0,
      overflow:'hidden',
      opacity: room.off ? 0.55 : 1,
    }}>
      <div style={{
        padding:'11px 12px 12px',
        borderBottom: !expanded ? `1px solid ${T.line}` : 'none',
      }}>
        {/* Line 1: identity + transport — name now gets the full row width */}
        <div style={{display:'flex', alignItems:'center', gap: 12}}>
          <HFIcon name={room.icon} size={18} color={T.ink2}/>
          <div style={{flex:1, minWidth:0}}>
            <div style={{display:'flex', alignItems:'center', gap: 6, minWidth:0}}>
              <span style={{fontSize: 14.5, fontWeight: 600, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{room.name}</span>
              {(room.group || room.groupedWith) && (
                <span style={{display:'inline-flex', alignItems:'center', gap: 3, fontSize: 10, fontWeight: 600, flexShrink:0,
                  padding:'1px 6px', borderRadius: 4, background: T.accentSoft, color: T.accent}}>
                  <HFIcon name="link" size={9} color={T.accent} strokeWidth={2.4}/>
                  {room.group ? `+${room.group.length}` : 'group'}
                </span>
              )}
              {room.playing && !room.group && !room.groupedWith && (
                <span style={{display:'inline-block', width: 6, height: 6, borderRadius:'50%', background: T.accent, flexShrink:0}}/>
              )}
            </div>
            <div style={{fontSize: 11, color: T.inkMute, marginTop: 1, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>
              {room.playing && room.song ? `${room.song} — ${room.artist}` :
                room.groupedWith ? `Grouped with ${room.groupedWith}` :
                room.off ? 'Powered off' :
                `${room.devices} · Idle`}
            </div>
          </div>
          {/* Explicit, bounded transport control (44px tap, distinct from the
              row's navigate-to-detail affordance to avoid competing targets) */}
          {!room.off && (
            <button style={{
              width: 44, height: 44, borderRadius: 999, padding: 0, flexShrink: 0,
              background:'transparent', border:'none', cursor:'pointer',
              display:'flex', alignItems:'center', justifyContent:'center',
            }}>
              <span style={{width: 34, height: 34, borderRadius: 999,
                background: T.fill, border:`1px solid ${T.line}`,
                display:'flex', alignItems:'center', justifyContent:'center'}}>
                <HFIcon name={room.playing ? 'pause' : 'play'} size={15} color={T.ink}/>
              </span>
            </button>
          )}
          {/* chevron = decorative affordance; the whole row is the >=44px tap target to Room detail */}
          <HFIcon name="chevron-right" size={12} color={T.inkFaint}/>
        </div>
        {/* Line 2: full-width per-room volume (hidden when powered off) */}
        {!room.off && (
          <div style={{display:'flex', alignItems:'center', gap: 10, marginTop: 10, paddingLeft: 30}}>
            <HFIcon name="volume" size={14} color={T.inkMute}/>
            <div style={{flex:1, minWidth:0}}>
              <HFSlider value={room.vol} h={4} showThumb={true}/>
            </div>
            <span style={{fontFamily: MONO, fontSize: 11, color: T.inkMute, width: 22, textAlign:'right', fontVariantNumeric:'tabular-nums'}}>{Math.round(room.vol*100)}</span>
          </div>
        )}
      </div>
    </div>
  );
};

// ---------- Adaptive bottom strip ----------
const V3BottomStrip = ({ sources }) => {
  const T = hfTokens();
  if (!sources || sources.length === 0) return null;

  if (sources.length === 1) {
    const s = sources[0];
    return (
      <div style={{
        margin:'0 12px 14px', padding:'8px 10px 8px 8px',
        background: T.elevated, border:`1px solid ${T.line}`, borderRadius: 14,
        display:'flex', alignItems:'center', gap: 12,
        boxShadow:'0 6px 18px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04)',
        flexShrink: 0,
      }}>
        <HFArt variant={s.art} size={42} radius={8}/>
        <div style={{flex:1, minWidth:0}}>
          <div style={{fontSize: 13, fontWeight: 600, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{s.song}</div>
          <div style={{fontSize: 11, color: T.inkMute, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{s.artist} · {s.label}</div>
        </div>
        <V3Tap><HFIcon name="prev" size={20} color={T.inkMute}/></V3Tap>
        <V3Tap><HFIcon name="pause" size={22}/></V3Tap>
        <V3Tap><HFIcon name="next" size={20} color={T.inkMute}/></V3Tap>
      </div>
    );
  }

  // multi-source: the floating bar grows UPWARD into a stack — one row per
  // active source. It's the single-source bar generalized (1 row = single).
  // Each row: art · what's playing · rooms · bounded play/pause; the text/art
  // taps through to that source's Now Playing (chevron = decorative affordance,
  // same pattern as the stack rows). Capped at 3 visible + a "+N more" row.
  const MAX = 3;
  const visible = sources.slice(0, MAX);
  const extra = sources.length - visible.length;
  return (
    <div style={{
      margin:'0 12px 14px',
      background: T.elevated, border:`1px solid ${T.line}`, borderRadius: 16,
      boxShadow:'0 8px 22px rgba(0,0,0,0.10), 0 1px 2px rgba(0,0,0,0.04)',
      overflow:'hidden', flexShrink: 0,
    }}>
      {/* header — identifies the stack and collapses back to the compact pill */}
      <div style={{
        padding:'9px 10px 9px 14px', display:'flex', alignItems:'center', gap: 8,
        borderBottom:`1px solid ${T.line}`,
      }}>
        <span style={{width: 6, height: 6, borderRadius:'50%', background: T.accent}}/>
        <span style={{fontSize: 11.5, fontWeight: 700, letterSpacing:'.01em', whiteSpace:'nowrap'}}>{sources.length} sources playing</span>
        <div style={{flex:1}}/>
        <V3Tap size={28}><HFIcon name="chevron-down" size={16} color={T.inkMute}/></V3Tap>
      </div>
      {/* one mini-row per source */}
      {visible.map((s, i) => (
        <div key={s.id} style={{
          padding:'8px 10px 8px 12px', display:'flex', alignItems:'center', gap: 11,
          borderBottom: (i < visible.length - 1 || extra > 0) ? `1px solid ${T.line}` : 'none',
        }}>
          <HFArt variant={s.art} size={38} radius={8}/>
          <div style={{flex:1, minWidth:0}}>
            <div style={{fontSize: 13, fontWeight: 600, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{s.song}</div>
            <div style={{fontSize: 11, color: T.inkMute, display:'flex', alignItems:'center', gap: 4, minWidth:0}}>
              {s.rooms > 1 && <HFIcon name="link" size={10} color={T.inkMute} strokeWidth={2}/>}
              <span style={{whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{s.artist} · {s.label}</span>
            </div>
          </div>
          <button style={{
            width: 44, height: 44, borderRadius: 999, padding: 0, flexShrink: 0,
            background:'transparent', border:'none', cursor:'pointer',
            display:'flex', alignItems:'center', justifyContent:'center',
          }}>
            <span style={{width: 34, height: 34, borderRadius: 999,
              background: T.fill, border:`1px solid ${T.line}`,
              display:'flex', alignItems:'center', justifyContent:'center'}}>
              <HFIcon name="pause" size={15} color={T.ink}/>
            </span>
          </button>
          {/* chevron = decorative; the row taps through to this source's Now Playing */}
          <HFIcon name="chevron-right" size={12} color={T.inkFaint}/>
        </div>
      ))}
      {/* overflow row when more than MAX sources are active */}
      {extra > 0 && (
        <button style={{
          width:'100%', padding:'10px 14px', background:'transparent', border:'none',
          cursor:'pointer', display:'flex', alignItems:'center', gap: 8,
          color: T.inkMute, fontSize: 11.5, fontWeight: 600,
        }}>
          <HFIcon name="kebab" size={14} color={T.inkMute}/>
          +{extra} more · manage all
        </button>
      )}
    </div>
  );
};

// ============================================================
// SCREEN A: Home (Cards layout)
// ============================================================
const V3HomeCards = ({ rooms = V3_ROOMS }) => {
  const T = hfTokens();
  return (
    <HFFrame>
      <V3HomeHeader layout="cards"/>
      <div style={{flex:1, overflow:'hidden', padding:'0 12px',
        display:'grid', gridTemplateColumns:'minmax(0,1fr) minmax(0,1fr)', gap: 10, alignContent:'start'}}>
        {rooms.map((r, i) => <V3CardRoom key={i} room={r}/>)}
      </div>
      <div style={{height: 8}}/>
      <V3BottomStrip sources={sourcesFromRooms(rooms)}/>
    </HFFrame>
  );
};

// ============================================================
// SCREEN B: Home (Stack layout)
// ============================================================
const V3HomeStack = ({ rooms = V3_ROOMS }) => {
  const T = hfTokens();
  return (
    <HFFrame>
      <V3HomeHeader layout="stack"/>
      <div style={{flex:1, overflow:'hidden', padding:'0 12px',
        display:'flex', flexDirection:'column'}}>
        {rooms.map((r, i) => <V3StackRow key={i} room={r} expanded={false}/>)}
      </div>
      <V3BottomStrip sources={sourcesFromRooms(rooms)}/>
    </HFFrame>
  );
};

// ============================================================
// SCREEN C: Home — single-source state (only the group plays)
// ============================================================
const V3HomeSingle = () => {
  const T = hfTokens();
  return (
    <HFFrame>
      <V3HomeHeader layout="cards"/>
      <div style={{flex:1, overflow:'hidden', padding:'0 12px',
        display:'grid', gridTemplateColumns:'minmax(0,1fr) minmax(0,1fr)', gap: 10, alignContent:'start'}}>
        {V3_ROOMS_SOLO.map((r, i) => <V3CardRoom key={i} room={r}/>)}
      </div>
      <div style={{height: 8}}/>
      <V3BottomStrip sources={sourcesFromRooms(V3_ROOMS_SOLO)}/>
    </HFFrame>
  );
};

// ============================================================
// SCREEN D: Now Playing
// ============================================================
const V3NowPlaying = () => {
  const T = hfTokens();
  return (
    <HFFrame>
      <div style={{padding:'4px 18px 6px', display:'flex', alignItems:'center', gap: 12}}>
        <V3IconBtn icon="chevron-down" iconSize={18}/>
        <div style={{flex:1, textAlign:'center', minWidth:0}}>
          <div style={{fontSize: 10.5, fontWeight: 600, letterSpacing:'.08em', textTransform:'uppercase', color: T.inkMute}}>Playing on</div>
          <div style={{display:'inline-flex', alignItems:'center', gap: 4, marginTop: 2}}>
            <HFIcon name="link" size={12} color={T.accent} strokeWidth={2}/>
            <span style={{fontSize: 13, fontWeight: 600, color: T.accent, whiteSpace:'nowrap'}}>Living Room + Kitchen</span>
          </div>
        </div>
        <V3IconBtn icon="queue" iconSize={17}/>
      </div>

      <div style={{padding:'0 24px 6px', display:'flex', justifyContent:'center'}}>
        <div style={{
          display:'inline-flex', alignItems:'center', gap: 6,
          padding:'4px 9px', borderRadius: 999,
          background: T.fillStrong, color: T.ink2,
          fontSize: 10.5, fontWeight: 600, letterSpacing:'.02em',
        }}>
          <span style={{width: 6, height: 6, borderRadius:'50%', background: T.spotify}}/>
          Spotify Connect · from iPhone
        </div>
      </div>

      <div style={{flex:1, padding:'12px 24px 16px', display:'flex', flexDirection:'column', gap: 18, overflow:'hidden', minHeight: 0}}>
        <div style={{display:'flex', justifyContent:'center'}}>
          <HFArt variant="noir" size={HF.W - 88} radius={12}/>
        </div>
        <div>
          <div style={{fontSize: 23, fontWeight: 700, letterSpacing:'-0.02em', lineHeight: 1.1}}>Black Star</div>
          <div style={{fontSize: 14, color: T.inkMute, marginTop: 5}}>Radiohead · The Bends · 1995</div>
        </div>
        <div style={{display:'flex', flexDirection:'column', gap: 6}}>
          <HFSlider value={0.34} h={3}/>
          <div style={{display:'flex', justifyContent:'space-between', fontFamily: MONO, fontSize: 11, color: T.inkMute, fontVariantNumeric:'tabular-nums'}}>
            <span>1:24</span><span>4:08</span>
          </div>
        </div>
        <div style={{display:'flex', alignItems:'center', justifyContent:'space-between'}}>
          <V3Tap><HFIcon name="shuffle" size={20}/></V3Tap>
          <V3Tap size={52}><HFIcon name="prev" size={30}/></V3Tap>
          <button style={{
            width: 60, height: 60, borderRadius:'50%', background: T.ink, border:'none',
            display:'flex', alignItems:'center', justifyContent:'center', cursor:'pointer',
            boxShadow:'0 8px 22px rgba(0,0,0,0.18)',
          }}><HFIcon name="pause" size={24} color={T.surface}/></button>
          <V3Tap size={52}><HFIcon name="next" size={30}/></V3Tap>
          <V3Tap><HFIcon name="repeat" size={20}/></V3Tap>
        </div>
        <div style={{padding:'12px 14px', background: T.surface, border:`1px solid ${T.line}`, borderRadius: 14,
          display:'flex', flexDirection:'column', gap: 10}}>
          <div style={{display:'flex', justifyContent:'space-between', alignItems:'center'}}>
            <div style={{display:'flex', alignItems:'center', gap: 8, minWidth:0}}>
              <HFIcon name="volume" size={14} color={T.ink2}/>
              <span style={{fontSize: 11, fontWeight: 700, letterSpacing:'.06em', color: T.ink2, whiteSpace:'nowrap'}}>GROUP VOLUME</span>
            </div>
            <span style={{fontFamily: MONO, fontSize: 12, color: T.ink2, fontVariantNumeric:'tabular-nums', fontWeight: 600}}>36</span>
          </div>
          <HFSlider value={0.36} h={5} accent={T.accent}/>
          <div style={{display:'flex', justifyContent:'space-between', alignItems:'center', paddingTop: 6, borderTop:`1px dashed ${T.line}`}}>
            <span style={{fontSize: 11.5, color: T.inkMute}}>Living Room · <span style={{fontFamily: MONO, color: T.ink2}}>42</span></span>
            <span style={{fontSize: 11.5, color: T.inkMute}}>Kitchen · <span style={{fontFamily: MONO, color: T.ink2}}>30</span></span>
          </div>
        </div>
      </div>
    </HFFrame>
  );
};

// ============================================================
// SCREEN E: Group rooms — inline editor (reachable from Home group bar)
// ============================================================
const V3Group = () => {
  const T = hfTokens();
  const rooms = [
    { name:'Living Room', icon:'soundbar', sub:'Hosting — Black Star',      sel:true, host:true },
    { name:'Kitchen',     icon:'speaker',  sub:'Currently grouped',          sel:true },
    { name:'Bedroom',     icon:'speaker',  sub:'Idle',                       sel:false },
    { name:'Office',      icon:'speaker',  sub:'Playing Strobe — Deadmau5',  sel:false, conflict:true },
    { name:'Patio',       icon:'speakers', sub:'Powered off',                sel:false, off:true },
    { name:'Bathroom',    icon:'speaker',  sub:'Idle',                       sel:false },
  ];
  return (
    <HFFrame>
      <div style={{padding:'4px 18px 14px', display:'flex', alignItems:'center', gap: 12}}>
        <V3IconBtn icon="x" iconSize={17}/>
        <div style={{flex:1, textAlign:'center'}}>
          <div style={{fontSize: 15, fontWeight: 700, letterSpacing:'-0.01em'}}>Group rooms</div>
          <div style={{fontSize: 11, color: T.inkMute, marginTop: 1}}>2 selected · Living Room hosts</div>
        </div>
        <button style={{
          padding:'8px 14px', borderRadius: 10, background: T.accent, border:'none',
          color: T.onAccent, fontSize: 13, fontWeight: 700, cursor:'pointer', flexShrink:0,
        }}>Save</button>
      </div>

      <div style={{padding:'0 16px 12px', fontSize: 12, color: T.inkMute}}>
        Tap a room to add or remove. Audio plays in sync across all selected rooms.
      </div>

      <div style={{flex:1, overflow:'hidden', padding:'0 16px 12px',
        display:'flex', flexDirection:'column', gap: 8}}>
        {rooms.map((r, i) => (
          <div key={i} style={{
            padding:'12px 14px', borderRadius: 14,
            background: r.sel ? T.accentSoft : T.surface,
            border:`1.2px solid ${r.sel ? T.accent : T.line}`,
            display:'flex', alignItems:'center', gap: 12,
            opacity: r.off ? 0.5 : 1,
          }}>
            <HFCheck on={r.sel}/>
            <HFIcon name={r.icon} size={18} color={T.ink2}/>
            <div style={{flex:1, minWidth:0}}>
              <div style={{display:'flex', alignItems:'center', gap: 8, minWidth:0}}>
                <span style={{fontSize: 14, fontWeight: r.host ? 700 : 600, whiteSpace:'nowrap'}}>{r.name}</span>
                {r.host && (
                  <span style={{fontSize: 9.5, fontWeight: 700, letterSpacing:'.06em', flexShrink:0,
                    padding:'2px 6px', borderRadius: 4, background: T.accent, color: T.onAccent}}>HOST</span>
                )}
              </div>
              <span style={{fontSize: 11.5, color: r.conflict ? T.danger : T.inkMute, whiteSpace:'nowrap'}}>
                {r.conflict ? '⚠ Will stop current playback' : r.sub}
              </span>
            </div>
          </div>
        ))}
      </div>

      <div style={{padding:'12px 18px 22px', borderTop:`1px solid ${T.line}`,
        background: T.surface, display:'flex', alignItems:'center', gap: 10}}>
        <button style={{
          flex:1, padding:'10px 12px', borderRadius: 10, background: 'transparent', border:`1px solid ${T.line}`,
          color: T.ink, fontSize: 12.5, fontWeight: 600, cursor:'pointer',
        }}>Stereo pair…</button>
        <button style={{
          flex:1, padding:'10px 12px', borderRadius: 10, background: 'transparent', border:`1px solid ${T.line}`,
          color: T.danger, fontSize: 12.5, fontWeight: 600, cursor:'pointer',
        }}>Ungroup all</button>
      </div>
    </HFFrame>
  );
};

// ============================================================
// SCREEN F: Room detail
// ============================================================
const V3RoomDetail = () => {
  const T = hfTokens();
  return (
    <HFFrame>
      <div style={{padding:'8px 18px 14px', display:'flex', alignItems:'center', gap: 12}}>
        <V3IconBtn icon="chevron-left" iconSize={18}/>
        <div style={{flex:1, minWidth:0}}>
          <div style={{fontSize: 19, fontWeight: 700, letterSpacing:'-0.015em'}}>Living Room</div>
          <div style={{fontSize: 11.5, color: T.inkMute, marginTop: 1}}>Beam · Era 300 ×2 · Sub Mini</div>
        </div>
        <V3IconBtn icon="kebab" iconSize={18}/>
      </div>

      <div style={{flex:1, overflow:'hidden', padding:'0 20px 20px',
        display:'flex', flexDirection:'column', gap: 18}}>

        <div style={{padding:'10px', background: T.surface, border:`1px solid ${T.line}`, borderRadius: 14,
          display:'flex', alignItems:'center', gap: 12}}>
          <HFArt variant="noir" size={48} radius={8}/>
          <div style={{flex:1, minWidth:0}}>
            <div style={{fontSize: 13, fontWeight: 600, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>Black Star</div>
            <div style={{fontSize: 11.5, color: T.inkMute, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>Radiohead · The Bends</div>
          </div>
          <V3Tap><HFIcon name="prev" size={18}/></V3Tap>
          <V3Tap><HFIcon name="pause" size={22}/></V3Tap>
          <V3Tap><HFIcon name="next" size={18}/></V3Tap>
        </div>

        <div style={{display:'flex', alignItems:'center', gap: 14}}>
          <HFIcon name="volume" size={18} color={T.ink2}/>
          <div style={{flex:1}}><HFSlider value={0.42} h={6} accent={T.accent}/></div>
          <span style={{fontFamily: MONO, fontSize: 14, fontWeight: 600, color: T.ink, width: 28, textAlign:'right', fontVariantNumeric:'tabular-nums'}}>42</span>
        </div>

        <div>
          <HFSectionHd>Sound</HFSectionHd>
          <HFRow icon="eq" label="Bass" right={
            <div style={{display:'flex', alignItems:'center', gap: 8, width: 140}}>
              <HFSlider value={0.5} h={4} accent={T.accent}/>
              <span style={{fontFamily: MONO, fontSize: 11.5, color: T.ink2, width: 18, textAlign:'right', fontVariantNumeric:'tabular-nums'}}>0</span>
            </div>
          }/>
          <HFRow icon="eq" label="Treble" right={
            <div style={{display:'flex', alignItems:'center', gap: 8, width: 140}}>
              <HFSlider value={0.62} h={4} accent={T.accent}/>
              <span style={{fontFamily: MONO, fontSize: 11.5, color: T.ink2, width: 18, textAlign:'right', fontVariantNumeric:'tabular-nums'}}>+2</span>
            </div>
          }/>
          <HFRow icon="moon" label="Night Sound" sub="Quiets loud passages" right={<HFToggle on/>}/>
          <HFRow icon="mic" label="Speech Enhancement" right={<HFToggle on={false}/>}/>
          <HFRow icon="wave" label="Loudness" right={<HFToggle on/>} last/>
        </div>

        <div>
          <HFSectionHd>TV & Surround</HFSectionHd>
          <HFRow icon="tv" label="Lip sync" sub="+12 ms"
            right={<HFIcon name="chevron-right" size={16} color={T.inkMute}/>}/>
          <HFRow icon="speakers" label="Surround levels" sub="Era 300 ×2"
            right={<HFIcon name="chevron-right" size={16} color={T.inkMute}/>} last/>
        </div>

        <div>
          <HFSectionHd>System</HFSectionHd>
          <HFRow icon="timer" label="Sleep timer" sub="Off"
            right={<HFIcon name="chevron-right" size={16} color={T.inkMute}/>}/>
          <HFRow icon="settings" label="TruePlay calibration" sub="Tuned · Mar 4"
            right={<HFIcon name="chevron-right" size={16} color={T.inkMute}/>} last/>
        </div>
      </div>
    </HFFrame>
  );
};

// ============================================================
// SCREEN G: Settings
// ============================================================
const V3Settings = () => {
  const T = hfTokens();
  return (
    <HFFrame>
      <div style={{padding:'8px 18px 14px', display:'flex', alignItems:'center', gap: 12}}>
        <V3IconBtn icon="chevron-left" iconSize={18}/>
        <div style={{flex:1, fontSize: 19, fontWeight: 700, letterSpacing:'-0.015em'}}>Settings</div>
      </div>

      <div style={{flex:1, overflow:'hidden', padding:'0 20px 20px',
        display:'flex', flexDirection:'column', gap: 18}}>

        <div>
          <HFSectionHd>Appearance</HFSectionHd>
          <HFRow icon="moon" label="Theme" sub="Match system"
            right={<HFIcon name="chevron-right" size={16} color={T.inkMute}/>}/>
          <HFRow icon="grid" label="Default home layout" sub="Cards"
            right={<HFIcon name="chevron-right" size={16} color={T.inkMute}/>} last/>
        </div>

        <div>
          <HFSectionHd>System</HFSectionHd>
          <HFRow icon="speakers" label="Devices" sub="10 connected"
            right={<HFIcon name="chevron-right" size={16} color={T.inkMute}/>}/>
          <HFRow icon="wifi" label="Network" sub="Local network · Strong"
            right={<HFIcon name="chevron-right" size={16} color={T.inkMute}/>}/>
          <HFRow icon="plus" label="Add a speaker"
            right={<HFIcon name="chevron-right" size={16} color={T.inkMute}/>} last/>
        </div>

        <div>
          <HFSectionHd>Privacy</HFSectionHd>
          <HFRow icon="settings" label="Send anonymous crash reports" right={<HFToggle on={false}/>}/>
          <HFRow icon="settings" label="Send usage diagnostics" right={<HFToggle on={false}/>} last/>
        </div>

        <div>
          <HFSectionHd>About</HFSectionHd>
          <HFRow icon="settings" label="Version" sub="0.4.2 (build 184)" last/>
        </div>
      </div>
    </HFFrame>
  );
};

// ============================================================
// SCREEN H: Queue
// ============================================================
const V3Queue = () => {
  const T = hfTokens();
  const queue = [
    { song:'Black Star',      artist:'Radiohead',   dur:'4:08', art:'noir',  playing:true },
    { song:'Fake Plastic Trees', artist:'Radiohead', dur:'4:51', art:'noir' },
    { song:'High and Dry',    artist:'Radiohead',   dur:'4:18', art:'noir' },
    { song:'Just',            artist:'Radiohead',   dur:'3:54', art:'ember' },
    { song:'Karma Police',    artist:'Radiohead',   dur:'4:23', art:'fog' },
    { song:'No Surprises',    artist:'Radiohead',   dur:'3:48', art:'mint' },
    { song:'Paranoid Android',artist:'Radiohead',   dur:'6:23', art:'noir' },
  ];
  return (
    <HFFrame>
      <div style={{padding:'4px 18px 12px', display:'flex', alignItems:'center', gap: 12}}>
        <V3IconBtn icon="chevron-down" iconSize={18}/>
        <div style={{flex:1, textAlign:'center'}}>
          <div style={{fontSize: 10.5, fontWeight: 600, letterSpacing:'.08em', textTransform:'uppercase', color: T.inkMute}}>Up next</div>
          <div style={{fontSize: 13, fontWeight: 600, marginTop: 1, whiteSpace:'nowrap'}}>Living Room + Kitchen</div>
        </div>
        <V3IconBtn icon="kebab" iconSize={17}/>
      </div>

      <div style={{padding:'0 18px 10px', display:'flex', gap: 8}}>
        <button style={{
          padding:'0 14px', minHeight: 44, borderRadius: 9, background: T.fill, border:`1px solid ${T.line}`,
          color: T.ink2, fontSize: 11.5, fontWeight: 600, cursor:'pointer',
          display:'inline-flex', alignItems:'center', gap: 6,
        }}><HFIcon name="shuffle" size={12} color={T.ink2}/> Shuffle</button>
        <button style={{
          padding:'0 14px', minHeight: 44, borderRadius: 9, background: T.fill, border:`1px solid ${T.line}`,
          color: T.ink2, fontSize: 11.5, fontWeight: 600, cursor:'pointer',
          display:'inline-flex', alignItems:'center', gap: 6,
        }}><HFIcon name="repeat" size={12} color={T.ink2}/> Repeat</button>
        <div style={{flex:1}}/>
        <button style={{
          padding:'0 14px', minHeight: 44, borderRadius: 9, background:'transparent', border:`1px solid ${T.line}`,
          color: T.danger, fontSize: 11.5, fontWeight: 600, cursor:'pointer',
          display:'inline-flex', alignItems:'center',
        }}>Clear</button>
      </div>

      <div style={{flex:1, overflow:'hidden', padding:'0 12px'}}>
        {queue.map((q, i) => (
          <div key={i} style={{
            padding:'8px 8px', borderRadius: 10,
            background: q.playing ? T.accentSoft : 'transparent',
            display:'flex', alignItems:'center', gap: 12,
          }}>
            <HFArt variant={q.art} size={40} radius={6}/>
            <div style={{flex:1, minWidth:0}}>
              <div style={{fontSize: 13, fontWeight: q.playing ? 700 : 600,
                color: q.playing ? T.accent : T.ink, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{q.song}</div>
              <div style={{fontSize: 11, color: q.playing ? T.accent : T.inkMute, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis', opacity: q.playing ? 0.85 : 1}}>{q.artist}</div>
            </div>
            <span style={{fontFamily: MONO, fontSize: 11, color: T.inkMute, fontVariantNumeric:'tabular-nums'}}>{q.dur}</span>
            <V3Tap size={36} style={{cursor:'grab'}}><HFIcon name="drag" size={16} color={T.inkMute}/></V3Tap>
          </div>
        ))}
      </div>
    </HFFrame>
  );
};

// ============================================================
// Merged GROUP card — a group is ONE source: one shared now-playing + one
// transport. Volume is the exception (per-room), so the card nests a group
// master plus each room's level. Past 4 rooms the per-room list caps with a
// "+N" overflow (full list lives in Room detail); the master stays reachable.
// ============================================================
const V3RoomLevel = ({ name, vol }) => {
  const T = hfTokens();
  return (
    <div style={{display:'flex', alignItems:'center', gap: 10}}>
      <span style={{fontSize: 12, color: T.ink2, width: 92, flexShrink:0,
        whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{name}</span>
      <div style={{flex:1, minWidth:0}}><HFSlider value={vol} h={4} showThumb={true}/></div>
      <span style={{fontFamily: MONO, fontSize: 11, color: T.inkMute, width: 22, textAlign:'right',
        fontVariantNumeric:'tabular-nums'}}>{Math.round(vol*100)}</span>
    </div>
  );
};

const V3GroupCard = ({ host, members, song, artist, art, groupVol }) => {
  const T = hfTokens();
  // Title is just the host name; the count badge + Room levels list convey
  // membership, so the name never truncates regardless of group size.
  const title = host;
  const MAXR = 4;
  const visible = members.slice(0, MAXR);
  const overflow = members.length - visible.length;
  return (
    <div style={{background: T.surface, border:`1px solid ${T.line}`, borderRadius: 16, overflow:'hidden'}}>
      {/* header — one source: shared art, name, now-playing + ONE transport */}
      <div style={{padding:'12px 12px 12px', display:'flex', alignItems:'center', gap: 11}}>
        <HFArt variant={art} size={46} radius={10}/>
        <div style={{flex:1, minWidth:0}}>
          <div style={{display:'flex', alignItems:'center', gap: 6, minWidth:0}}>
            <span style={{fontSize: 14.5, fontWeight: 600, flexShrink: 0, maxWidth: 168, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{title}</span>
            <span style={{display:'inline-flex', alignItems:'center', gap: 3, fontSize: 10, fontWeight: 600, flexShrink:0,
              padding:'1px 6px', borderRadius: 4, background: T.accentSoft, color: T.accent}}>
              <HFIcon name="link" size={9} color={T.accent} strokeWidth={2.4}/>
              {members.length}
            </span>
          </div>
          <div style={{fontSize: 11.5, color: T.inkMute, marginTop: 2, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>
            {song} — {artist}
          </div>
        </div>
        <button style={{
          width: 44, height: 44, borderRadius: 999, padding: 0, flexShrink: 0,
          background:'transparent', border:'none', cursor:'pointer',
          display:'flex', alignItems:'center', justifyContent:'center',
        }}>
          <span style={{width: 34, height: 34, borderRadius: 999, background: T.fill, border:`1px solid ${T.line}`,
            display:'flex', alignItems:'center', justifyContent:'center'}}>
            <HFIcon name="pause" size={15} color={T.ink}/>
          </span>
        </button>
        <HFIcon name="chevron-right" size={12} color={T.inkFaint}/>
      </div>

      {/* volume — group master (always) + per-room levels */}
      <div style={{padding:'12px 14px 14px', borderTop:`1px solid ${T.line}`, display:'flex', flexDirection:'column', gap: 12}}>
        <div>
          <div style={{display:'flex', alignItems:'center', gap: 8, marginBottom: 7}}>
            <HFIcon name="volume" size={14} color={T.ink2}/>
            <span style={{fontSize: 10.5, fontWeight: 700, letterSpacing:'.06em', color: T.ink2, whiteSpace:'nowrap'}}>GROUP VOLUME</span>
            <div style={{flex:1}}/>
            <span style={{fontFamily: MONO, fontSize: 11.5, color: T.ink2, fontVariantNumeric:'tabular-nums', fontWeight: 600}}>{Math.round(groupVol*100)}</span>
          </div>
          <HFSlider value={groupVol} h={5} showThumb={true}/>
        </div>
        <div style={{display:'flex', flexDirection:'column', gap: 9}}>
          <span style={{fontSize: 9.5, fontWeight: 700, letterSpacing:'.07em', color: T.inkFaint}}>ROOM LEVELS</span>
          {visible.map((m, i) => <V3RoomLevel key={i} name={m.name} vol={m.vol}/>)}
          {overflow > 0 && (
            <button style={{
              alignSelf:'flex-start', background:'transparent', border:'none', cursor:'pointer',
              padding:'2px 0', color: T.accent, fontSize: 11.5, fontWeight: 600,
              display:'inline-flex', alignItems:'center', gap: 4, whiteSpace:'nowrap',
            }}>+{overflow} more {overflow === 1 ? 'room' : 'rooms'}<span style={{color: T.inkFaint, fontWeight: 500}}>&nbsp;· room detail</span></button>
          )}
        </div>
      </div>
    </div>
  );
};

// Demo wrapper — builds an N-room group from a pool so we can compare counts.
const V3GroupDemo = ({ count = 2 }) => {
  const T = hfTokens();
  const pool = [
    { name:'Living Room', vol:0.42 }, { name:'Kitchen', vol:0.30 },
    { name:'Dining Room', vol:0.36 }, { name:'Office', vol:0.55 },
    { name:'Bedroom', vol:0.18 }, { name:'Patio', vol:0.48 },
  ];
  return (
    <div style={{padding: 16, background: T.bg, minHeight:'100%', boxSizing:'border-box',
      fontFamily: FONT, color: T.ink, WebkitFontSmoothing:'antialiased', letterSpacing:'-0.005em'}}>
      <V3GroupCard host="Living Room" members={pool.slice(0, count)}
        song="Black Star" artist="Radiohead" art="noir" groupVol={0.36}/>
    </div>
  );
};

Object.assign(window, {
  V3HomeCards, V3HomeStack, V3HomeSingle, V3HomeHeader,
  V3NowPlaying, V3Group, V3RoomDetail, V3Settings, V3Queue,
  V3GroupCard, V3GroupDemo,
  OtoMark, V3Tap,
});
