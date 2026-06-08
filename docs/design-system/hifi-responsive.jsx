// Tablet and desktop layouts
// Reuses everything from hifi-primitives + hifi-unified

const TABLET = { W: 1024, H: 768 };
const DESKTOP = { W: 1440, H: 900 };

// ============================================================
// Shared: room list item used in side panels
// ============================================================
const PaneRoomRow = ({ room, active, dense }) => {
  const T = hfTokens();
  return (
    <div style={{
      padding: dense ? '9px 12px' : '11px 14px',
      borderRadius: 10,
      background: active ? T.accentSoft : 'transparent',
      display:'flex', alignItems:'center', gap: 11,
      opacity: room.off ? 0.55 : 1,
      cursor:'pointer',
      border: active ? `1px solid ${T.accent}` : '1px solid transparent',
    }}>
      <HFIcon name={room.icon} size={16} color={active ? T.accent : T.ink2}/>
      <div style={{flex:1, minWidth:0}}>
        <div style={{display:'flex', alignItems:'center', gap: 6, minWidth:0}}>
          <span style={{
            fontSize: 13.5, fontWeight: active ? 700 : 600,
            color: active ? T.accent : T.ink,
            whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis',
          }}>{room.name}</span>
          {(room.group || room.groupedWith) && (
            <span style={{display:'inline-flex', alignItems:'center', gap: 3, flexShrink:0,
              fontSize: 9.5, fontWeight: 700, padding:'1px 5px', borderRadius: 3,
              background: T.accentSoft, color: T.accent}}>
              <HFIcon name="link" size={8} color={T.accent} strokeWidth={2.4}/>
            </span>
          )}
          {room.playing && !room.group && !room.groupedWith && (
            <span style={{width: 6, height: 6, borderRadius:'50%', background: T.accent, flexShrink:0}}/>
          )}
        </div>
        <div style={{fontSize: 10.5, color: active ? T.accent : T.inkMute, opacity: active?0.85:1,
          marginTop: 1, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>
          {room.playing && room.song ? `${room.song} — ${room.artist}` :
            room.groupedWith ? `Grouped with ${room.groupedWith}` :
            room.off ? 'Powered off' : 'Idle'}
        </div>
      </div>
      <div style={{width: 52, display:'flex', alignItems:'center', gap: 4, flexShrink:0}}>
        <HFSlider value={room.vol} h={3} showThumb={false}/>
      </div>
    </div>
  );
};

const PaneFrame = ({ width, height, children }) => {
  const T = hfTokens();
  return (
    <div style={{
      width, height, background: T.bg, color: T.ink,
      fontFamily: FONT, fontSize: 14, overflow:'hidden',
      display:'flex', flexDirection:'column',
      WebkitFontSmoothing:'antialiased', letterSpacing:'-0.005em',
      border:`1px solid ${T.lineStrong}`, borderRadius: 8,
    }}>{children}</div>
  );
};

const PaneTopBar = ({ rooms, playing, showBack, title }) => {
  const T = hfTokens();
  return (
    <div style={{
      height: 56, padding:'0 18px', display:'flex', alignItems:'center', gap: 14,
      borderBottom:`1px solid ${T.line}`, flexShrink: 0, background: T.surface,
    }}>
      <div style={{
        width: 28, height: 28, borderRadius: 7,
        display:'flex', alignItems:'center', justifyContent:'center', flexShrink: 0,
      }}><OtoMark size={26}/></div>
      <div style={{fontSize: 14, fontWeight: 700, letterSpacing:'-0.01em'}}>{title || 'oto'}</div>
      <div style={{flex:1}}/>
      <div style={{
        display:'flex', alignItems:'center', gap: 8,
        padding:'6px 12px', borderRadius: 8, background: T.fill, minWidth: 220,
      }}>
        <HFIcon name="search" size={14} color={T.inkMute}/>
        <span style={{fontSize: 12.5, color: T.inkFaint}}>Search rooms, songs…</span>
        <span style={{flex:1}}/>
        <span style={{fontFamily: MONO, fontSize: 10.5, color: T.inkFaint,
          padding:'2px 5px', borderRadius: 4, background: T.fillStrong}}>⌘K</span>
      </div>
      <button style={{
        width: 32, height: 32, borderRadius: 8, border:`1px solid ${T.line}`,
        background:'transparent', display:'flex', alignItems:'center', justifyContent:'center',
        color: T.ink2, cursor:'pointer',
      }}><HFIcon name="settings" size={15}/></button>
    </div>
  );
};

// ============================================================
// Tablet — master/detail (Now Playing focus)
// ============================================================
const V3Tablet = () => {
  const T = hfTokens();
  const W = TABLET.W, H = TABLET.H;
  const SIDEBAR = 332;
  return (
    <PaneFrame width={W} height={H}>
      <PaneTopBar/>
      <div style={{flex:1, display:'flex', minHeight: 0}}>
        {/* Sidebar */}
        <div style={{
          width: SIDEBAR, borderRight:`1px solid ${T.line}`, background: T.surface,
          display:'flex', flexDirection:'column', minHeight: 0,
        }}>
          <div style={{padding:'14px 16px 8px', display:'flex', alignItems:'center', gap: 8}}>
            <div style={{flex:1, fontSize: 12.5, fontWeight: 700, letterSpacing:'.06em', color: T.inkMute, textTransform:'uppercase'}}>Rooms</div>
            <button style={{
              padding:'4px 9px', borderRadius: 7, background: T.fill, border:`1px solid ${T.line}`,
              color: T.ink2, fontSize: 11, fontWeight: 600, cursor:'pointer',
              display:'inline-flex', alignItems:'center', gap: 4,
            }}><HFIcon name="link" size={11} color={T.ink2} strokeWidth={2}/> Group</button>
          </div>
          <div style={{flex:1, overflow:'hidden', padding:'4px 8px', display:'flex', flexDirection:'column', gap: 2}}>
            {V3_ROOMS.map((r, i) => (
              <PaneRoomRow key={i} room={r} active={i === 0} dense/>
            ))}
          </div>
          <div style={{
            padding:'10px 14px', borderTop:`1px solid ${T.line}`, background: T.surface2,
            display:'flex', alignItems:'center', gap: 10,
          }}>
            <span style={{width: 6, height: 6, borderRadius:'50%', background: T.success}}/>
            <span style={{fontSize: 11, color: T.inkMute}}>Local · 10 devices online</span>
          </div>
        </div>

        {/* Detail = Now Playing */}
        <div style={{flex:1, display:'flex', flexDirection:'column', minWidth: 0, background: T.bg}}>
          <div style={{
            padding:'14px 22px', display:'flex', alignItems:'center', gap: 14,
            borderBottom:`1px solid ${T.line}`,
          }}>
            <div style={{flex:1, minWidth:0}}>
              <div style={{fontSize: 19, fontWeight: 700, letterSpacing:'-0.02em'}}>Living Room + Kitchen</div>
              <div style={{fontSize: 11.5, color: T.inkMute, marginTop: 2, display:'flex', alignItems:'center', gap: 8}}>
                <span style={{display:'inline-flex', alignItems:'center', gap: 4}}>
                  <HFIcon name="link" size={11} color={T.accent} strokeWidth={2}/>
                  <span style={{color: T.accent, fontWeight: 600}}>2 rooms grouped</span>
                </span>
                <span style={{color: T.inkFaint}}>·</span>
                <span style={{display:'inline-flex', alignItems:'center', gap: 5}}>
                  <span style={{width:6, height:6, borderRadius:'50%', background: T.spotify}}/>
                  Spotify Connect from iPhone
                </span>
              </div>
            </div>
            <button style={{
              padding:'8px 14px', borderRadius: 9, background:'transparent',
              border:`1px solid ${T.line}`, color: T.ink2,
              fontSize: 12.5, fontWeight: 600, cursor:'pointer',
              display:'inline-flex', alignItems:'center', gap: 6,
            }}><HFIcon name="queue" size={13} color={T.ink2}/> Queue</button>
            <button style={{
              width: 36, height: 36, borderRadius: 9, border:`1px solid ${T.line}`,
              background:'transparent', color: T.ink2, cursor:'pointer',
              display:'inline-flex', alignItems:'center', justifyContent:'center',
            }}><HFIcon name="kebab" size={16}/></button>
          </div>

          <div style={{flex:1, padding:'28px 36px', display:'flex', gap: 36, alignItems:'center', minHeight: 0}}>
            <HFArt variant="noir" size={280} radius={14}/>
            <div style={{flex:1, display:'flex', flexDirection:'column', gap: 22, minWidth: 0}}>
              <div>
                <div style={{fontSize: 34, fontWeight: 700, letterSpacing:'-0.025em', lineHeight: 1.05}}>Black Star</div>
                <div style={{fontSize: 15, color: T.inkMute, marginTop: 6}}>Radiohead · The Bends · 1995</div>
              </div>
              <div style={{display:'flex', flexDirection:'column', gap: 6}}>
                <HFSlider value={0.34} h={4} accent={T.accent}/>
                <div style={{display:'flex', justifyContent:'space-between', fontFamily: MONO, fontSize: 11.5, color: T.inkMute, fontVariantNumeric:'tabular-nums'}}>
                  <span>1:24</span><span>4:08</span>
                </div>
              </div>
              <div style={{display:'flex', alignItems:'center', gap: 28}}>
                <V3Tap><HFIcon name="shuffle" size={20}/></V3Tap>
                <V3Tap size={52}><HFIcon name="prev" size={32}/></V3Tap>
                <button style={{
                  width: 60, height: 60, borderRadius:'50%', background: T.ink, border:'none',
                  display:'flex', alignItems:'center', justifyContent:'center', cursor:'pointer',
                  boxShadow:'0 8px 22px rgba(0,0,0,0.18)',
                }}><HFIcon name="pause" size={24} color={T.surface}/></button>
                <V3Tap size={52}><HFIcon name="next" size={32}/></V3Tap>
                <V3Tap><HFIcon name="repeat" size={20}/></V3Tap>
              </div>
              <div style={{padding:'14px 16px', background: T.surface, border:`1px solid ${T.line}`, borderRadius: 12,
                display:'flex', flexDirection:'column', gap: 10}}>
                <div style={{display:'flex', justifyContent:'space-between', alignItems:'center'}}>
                  <div style={{display:'flex', alignItems:'center', gap: 8}}>
                    <HFIcon name="volume" size={14} color={T.ink2}/>
                    <span style={{fontSize: 11, fontWeight: 700, letterSpacing:'.06em', color: T.ink2}}>GROUP VOLUME</span>
                  </div>
                  <span style={{fontFamily: MONO, fontSize: 12, color: T.ink2, fontVariantNumeric:'tabular-nums', fontWeight: 600}}>36</span>
                </div>
                <HFSlider value={0.36} h={5} accent={T.accent}/>
                <div style={{display:'flex', justifyContent:'space-between', alignItems:'center', paddingTop: 8, borderTop:`1px dashed ${T.line}`, fontSize: 11.5, color: T.inkMute}}>
                  <span>Living Room · <span style={{fontFamily: MONO, color: T.ink2}}>42</span></span>
                  <span>Kitchen · <span style={{fontFamily: MONO, color: T.ink2}}>30</span></span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </PaneFrame>
  );
};

// ============================================================
// Desktop — three pane (rooms / detail / queue)
// ============================================================
const V3Desktop = () => {
  const T = hfTokens();
  const W = DESKTOP.W, H = DESKTOP.H;
  const queue = [
    { song:'Black Star',      artist:'Radiohead',   dur:'4:08', art:'noir',  playing:true },
    { song:'Fake Plastic Trees', artist:'Radiohead', dur:'4:51', art:'noir' },
    { song:'High and Dry',    artist:'Radiohead',   dur:'4:18', art:'noir' },
    { song:'Just',            artist:'Radiohead',   dur:'3:54', art:'ember' },
    { song:'Karma Police',    artist:'Radiohead',   dur:'4:23', art:'fog' },
    { song:'No Surprises',    artist:'Radiohead',   dur:'3:48', art:'mint' },
    { song:'Paranoid Android',artist:'Radiohead',   dur:'6:23', art:'noir' },
    { song:'Lucky',           artist:'Radiohead',   dur:'4:19', art:'fog' },
  ];
  return (
    <PaneFrame width={W} height={H}>
      <PaneTopBar/>
      <div style={{flex:1, display:'flex', minHeight: 0}}>

        {/* Left: rooms */}
        <div style={{
          width: 340, borderRight:`1px solid ${T.line}`, background: T.surface,
          display:'flex', flexDirection:'column', minHeight: 0,
        }}>
          <div style={{padding:'16px 18px 10px', display:'flex', alignItems:'center', gap: 10}}>
            <div style={{flex:1, fontSize: 12.5, fontWeight: 700, letterSpacing:'.06em', color: T.inkMute, textTransform:'uppercase'}}>Rooms · 6</div>
            <button style={{
              padding:'5px 10px', borderRadius: 7, background: T.fill, border:`1px solid ${T.line}`,
              color: T.ink2, fontSize: 11.5, fontWeight: 600, cursor:'pointer',
              display:'inline-flex', alignItems:'center', gap: 5,
            }}><HFIcon name="link" size={11} color={T.ink2} strokeWidth={2}/> Group</button>
          </div>
          <div style={{flex:1, overflow:'hidden', padding:'4px 10px', display:'flex', flexDirection:'column', gap: 3}}>
            {V3_ROOMS.map((r, i) => (
              <PaneRoomRow key={i} room={r} active={i === 0}/>
            ))}
          </div>
          <div style={{
            padding:'12px 16px', borderTop:`1px solid ${T.line}`, background: T.surface2,
            display:'flex', alignItems:'center', gap: 10,
          }}>
            <span style={{width: 6, height: 6, borderRadius:'50%', background: T.success}}/>
            <span style={{fontSize: 11, color: T.inkMute, flex:1}}>Local · UPnP events live</span>
          </div>
        </div>

        {/* Center: Now Playing + per-room controls */}
        <div style={{flex:1, display:'flex', flexDirection:'column', minWidth: 0, background: T.bg}}>
          <div style={{
            padding:'18px 28px 14px', borderBottom:`1px solid ${T.line}`,
            display:'flex', alignItems:'center', gap: 14,
          }}>
            <div style={{flex:1, minWidth:0}}>
              <div style={{fontSize: 22, fontWeight: 700, letterSpacing:'-0.02em'}}>Living Room + Kitchen</div>
              <div style={{fontSize: 11.5, color: T.inkMute, marginTop: 3, display:'flex', alignItems:'center', gap: 10}}>
                <span style={{display:'inline-flex', alignItems:'center', gap: 4}}>
                  <HFIcon name="link" size={11} color={T.accent} strokeWidth={2}/>
                  <span style={{color: T.accent, fontWeight: 600}}>Living Room hosts</span>
                </span>
                <span style={{color: T.inkFaint}}>·</span>
                <span style={{display:'inline-flex', alignItems:'center', gap: 5}}>
                  <span style={{width:6, height:6, borderRadius:'50%', background: T.spotify}}/>
                  Spotify Connect from iPhone
                </span>
              </div>
            </div>
            <button style={{
              padding:'8px 14px', borderRadius: 9, background:'transparent',
              border:`1px solid ${T.line}`, color: T.ink2,
              fontSize: 12.5, fontWeight: 600, cursor:'pointer',
              display:'inline-flex', alignItems:'center', gap: 6,
            }}><HFIcon name="sliders" size={13} color={T.ink2}/> Sound</button>
            <button style={{
              width: 36, height: 36, borderRadius: 9, border:`1px solid ${T.line}`,
              background:'transparent', color: T.ink2, cursor:'pointer',
              display:'inline-flex', alignItems:'center', justifyContent:'center',
            }}><HFIcon name="kebab" size={16}/></button>
          </div>

          <div style={{flex:1, padding:'30px 36px', display:'flex', gap: 32, minHeight: 0, overflow:'hidden'}}>
            <HFArt variant="noir" size={320} radius={14}/>
            <div style={{flex:1, display:'flex', flexDirection:'column', gap: 20, minWidth: 0}}>
              <div>
                <div style={{fontSize: 38, fontWeight: 700, letterSpacing:'-0.025em', lineHeight: 1.05}}>Black Star</div>
                <div style={{fontSize: 16, color: T.inkMute, marginTop: 6}}>Radiohead · The Bends · 1995</div>
              </div>
              <div style={{display:'flex', flexDirection:'column', gap: 6}}>
                <HFSlider value={0.34} h={4} accent={T.accent}/>
                <div style={{display:'flex', justifyContent:'space-between', fontFamily: MONO, fontSize: 12, color: T.inkMute, fontVariantNumeric:'tabular-nums'}}>
                  <span>1:24</span><span>4:08</span>
                </div>
              </div>
              <div style={{display:'flex', alignItems:'center', gap: 30}}>
                <V3Tap><HFIcon name="shuffle" size={20}/></V3Tap>
                <V3Tap size={52}><HFIcon name="prev" size={34}/></V3Tap>
                <button style={{
                  width: 64, height: 64, borderRadius:'50%', background: T.ink, border:'none',
                  display:'flex', alignItems:'center', justifyContent:'center', cursor:'pointer',
                  boxShadow:'0 10px 24px rgba(0,0,0,0.18)',
                }}><HFIcon name="pause" size={26} color={T.surface}/></button>
                <V3Tap size={52}><HFIcon name="next" size={34}/></V3Tap>
                <V3Tap><HFIcon name="repeat" size={20}/></V3Tap>
              </div>
              <div style={{padding:'16px 18px', background: T.surface, border:`1px solid ${T.line}`, borderRadius: 12,
                display:'flex', flexDirection:'column', gap: 12, marginTop: 4}}>
                <div style={{display:'flex', justifyContent:'space-between', alignItems:'center'}}>
                  <div style={{display:'flex', alignItems:'center', gap: 10}}>
                    <HFIcon name="volume" size={15} color={T.ink2}/>
                    <span style={{fontSize: 11.5, fontWeight: 700, letterSpacing:'.06em', color: T.ink2}}>GROUP VOLUME</span>
                  </div>
                  <span style={{fontFamily: MONO, fontSize: 13, color: T.ink, fontVariantNumeric:'tabular-nums', fontWeight: 700}}>36</span>
                </div>
                <HFSlider value={0.36} h={6} accent={T.accent}/>
                <div style={{display:'grid', gridTemplateColumns:'1fr 1fr', gap: 14, paddingTop: 10, borderTop:`1px dashed ${T.line}`}}>
                  <div style={{display:'flex', alignItems:'center', gap: 10}}>
                    <span style={{fontSize: 11.5, color: T.ink2, width: 78}}>Living Room</span>
                    <div style={{flex:1}}><HFSlider value={0.42} h={3} showThumb={false}/></div>
                    <span style={{fontFamily: MONO, fontSize: 11, color: T.inkMute, width: 18, textAlign:'right'}}>42</span>
                  </div>
                  <div style={{display:'flex', alignItems:'center', gap: 10}}>
                    <span style={{fontSize: 11.5, color: T.ink2, width: 78}}>Kitchen</span>
                    <div style={{flex:1}}><HFSlider value={0.30} h={3} showThumb={false}/></div>
                    <span style={{fontFamily: MONO, fontSize: 11, color: T.inkMute, width: 18, textAlign:'right'}}>30</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Right: Queue */}
        <div style={{
          width: 360, borderLeft:`1px solid ${T.line}`, background: T.surface,
          display:'flex', flexDirection:'column', minHeight: 0,
        }}>
          <div style={{padding:'16px 18px 10px', display:'flex', alignItems:'center', gap: 10}}>
            <div style={{flex:1}}>
              <div style={{fontSize: 12.5, fontWeight: 700, letterSpacing:'.06em', color: T.inkMute, textTransform:'uppercase'}}>Up next</div>
              <div style={{fontSize: 11, color: T.inkFaint, marginTop: 2}}>8 tracks · 35 min</div>
            </div>
            <button style={{
              padding:'4px 8px', borderRadius: 6, background:'transparent',
              border:`1px solid ${T.line}`, color: T.inkMute,
              fontSize: 10.5, fontWeight: 600, cursor:'pointer',
            }}>Clear</button>
          </div>
          <div style={{padding:'4px 10px 10px', display:'flex', gap: 6}}>
            <button style={{
              padding:'5px 9px', borderRadius: 7, background: T.fill, border:`1px solid ${T.line}`,
              color: T.ink2, fontSize: 11, fontWeight: 600, cursor:'pointer',
              display:'inline-flex', alignItems:'center', gap: 4,
            }}><HFIcon name="shuffle" size={11} color={T.ink2}/> Shuffle</button>
            <button style={{
              padding:'5px 9px', borderRadius: 7, background: T.fill, border:`1px solid ${T.line}`,
              color: T.ink2, fontSize: 11, fontWeight: 600, cursor:'pointer',
              display:'inline-flex', alignItems:'center', gap: 4,
            }}><HFIcon name="repeat" size={11} color={T.ink2}/> Repeat</button>
          </div>
          <div style={{flex:1, overflow:'hidden', padding:'0 8px'}}>
            {queue.map((q, i) => (
              <div key={i} style={{
                padding:'8px 8px', borderRadius: 8,
                background: q.playing ? T.accentSoft : 'transparent',
                display:'flex', alignItems:'center', gap: 10,
              }}>
                <HFArt variant={q.art} size={36} radius={6}/>
                <div style={{flex:1, minWidth:0}}>
                  <div style={{fontSize: 12.5, fontWeight: q.playing ? 700 : 600,
                    color: q.playing ? T.accent : T.ink, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{q.song}</div>
                  <div style={{fontSize: 10.5, color: q.playing ? T.accent : T.inkMute, opacity: q.playing? 0.85:1, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{q.artist}</div>
                </div>
                <span style={{fontFamily: MONO, fontSize: 10.5, color: T.inkMute, fontVariantNumeric:'tabular-nums'}}>{q.dur}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </PaneFrame>
  );
};

Object.assign(window, { V3Tablet, V3Desktop, TABLET, DESKTOP });
