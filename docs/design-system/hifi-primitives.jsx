// Hi-fi primitives — theme, type, icons, components, album art
// Reads theme from window.__hfTheme = { dark, accent }

const HF = { W: 390, H: 844 };

const ACCENTS = {
  teal:   { light: '#0f7a72', dark: '#5dd6c8' },
  indigo: { light: '#3f4cb8', dark: '#8a96ff' },
  amber:  { light: '#a85a1a', dark: '#f0b070' },
  slate:  { light: '#3a4554', dark: '#a8b3c2' },
};

const hfTokens = () => {
  const dark = window.__hfTheme?.dark;
  const accentKey = window.__hfTheme?.accent || 'teal';
  const accentDef = ACCENTS[accentKey];
  // Accept a known key ('teal'…) or fall back to a raw color string, so an
  // unmapped accent can never throw and blank the whole UI.
  const accent = accentDef ? accentDef[dark ? 'dark' : 'light']
    : (typeof accentKey === 'string' && accentKey[0] === '#' ? accentKey : ACCENTS.teal[dark ? 'dark' : 'light']);
  return dark ? {
    bg:        '#0e0e10',
    surface:   '#16161a',
    surface2:  '#1d1d22',
    elevated:  '#22222a',
    line:      'rgba(255,255,255,0.07)',
    lineStrong:'rgba(255,255,255,0.14)',
    ink:       'rgba(255,255,255,0.95)',
    ink2:      'rgba(255,255,255,0.78)',
    inkMute:   'rgba(255,255,255,0.62)',
    inkFaint:  'rgba(255,255,255,0.46)',
    accent,
    accentSoft:`color-mix(in oklab, ${accent} 22%, transparent)`,
    fill:      'rgba(255,255,255,0.04)',
    fillStrong:'rgba(255,255,255,0.10)',
    onAccent:  '#0e0e10',
    danger:    '#e08a7a',
    success:   '#5cc497',
    spotify:   '#1db954',
  } : {
    bg:        '#f6f5f1',
    surface:   '#ffffff',
    surface2:  '#f0eee9',
    elevated:  '#ffffff',
    line:      'rgba(20,20,20,0.07)',
    lineStrong:'rgba(20,20,20,0.16)',
    ink:       'rgba(15,15,15,0.96)',
    ink2:      'rgba(15,15,15,0.78)',
    inkMute:   'rgba(15,15,15,0.58)',
    inkFaint:  'rgba(15,15,15,0.46)',
    accent,
    accentSoft:`color-mix(in oklab, ${accent} 14%, transparent)`,
    fill:      'rgba(20,20,20,0.035)',
    fillStrong:'rgba(20,20,20,0.07)',
    onAccent:  '#ffffff',
    danger:    '#b34a3a',
    success:   '#3ea76f',
    spotify:   '#1db954',
  };
};

const FONT = `"Geist","Inter",ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif`;
const MONO = `"Geist Mono",ui-monospace,SFMono-Regular,Menlo,monospace`;

const HFFrame = ({ children, bg, noStatus }) => {
  const T = hfTokens();
  return (
    <div style={{
      width: HF.W, height: HF.H, background: bg || T.bg, color: T.ink,
      fontFamily: FONT, fontSize: 14, position: 'relative', overflow: 'hidden',
      display: 'flex', flexDirection: 'column',
      WebkitFontSmoothing:'antialiased', letterSpacing:'-0.005em',
    }}>
      {!noStatus && <HFStatus/>}
      <div style={{flex:1, display:'flex', flexDirection:'column', minHeight:0, position:'relative'}}>{children}</div>
    </div>
  );
};

const HFStatus = () => {
  const T = hfTokens();
  return (
    <div style={{
      height: 44, padding: '0 22px', display:'flex',
      justifyContent:'space-between', alignItems:'center',
      fontSize: 14, color: T.ink, flexShrink: 0, paddingTop: 6,
    }}>
      <span style={{fontFamily: MONO, fontWeight: 600, fontVariantNumeric:'tabular-nums'}}>9:41</span>
      <span style={{display:'flex', gap: 5, alignItems:'center'}}>
        <HFIcon name="signal" size={14}/>
        <HFIcon name="wifi" size={14}/>
        <span style={{width: 22, height: 10, border:`1.2px solid ${T.ink}`, borderRadius: 2.5, position:'relative', display:'inline-block'}}>
          <span style={{position:'absolute', inset: 1.2, right: 4, background: T.ink, borderRadius: 1}}/>
          <span style={{position:'absolute', right:-3, top: 3.2, width: 2, height: 3.6, background: T.ink, borderRadius:'0 1px 1px 0'}}/>
        </span>
      </span>
    </div>
  );
};

const HFIcon = ({ name, size = 18, color, strokeWidth }) => {
  const T = hfTokens();
  const c = color || T.ink;
  const sw = strokeWidth || 1.6;
  const p = { width: size, height: size, viewBox:'0 0 24 24', fill:'none',
    stroke: c, strokeWidth: sw, strokeLinecap:'round', strokeLinejoin:'round',
    style: { display:'block', flexShrink:0 } };
  switch (name) {
    case 'play':     return <svg {...p}><path d="M7 5 L19 12 L7 19 Z" fill={c} stroke="none"/></svg>;
    case 'pause':    return <svg {...p}><rect x="6.5" y="5" width="3.5" height="14" rx="1" fill={c} stroke="none"/><rect x="14" y="5" width="3.5" height="14" rx="1" fill={c} stroke="none"/></svg>;
    case 'next':     return <svg {...p}><path d="M5 5 L15 12 L5 19 Z" fill={c} stroke="none"/><rect x="16" y="5" width="2.5" height="14" rx="0.6" fill={c} stroke="none"/></svg>;
    case 'prev':     return <svg {...p}><path d="M19 5 L9 12 L19 19 Z" fill={c} stroke="none"/><rect x="5.5" y="5" width="2.5" height="14" rx="0.6" fill={c} stroke="none"/></svg>;
    case 'shuffle':  return <svg {...p}><path d="M3 7 H6 L11 17 H14 M3 17 H6 L8 14 M14 7 H17 L11.5 17"/><path d="M14 5 L17 7 L14 9 M14 15 L17 17 L14 19"/></svg>;
    case 'repeat':   return <svg {...p}><path d="M5 9 V8 A2 2 0 0 1 7 6 H19 L16 3 M19 15 V16 A2 2 0 0 1 17 18 H5 L8 21"/></svg>;
    case 'volume':   return <svg {...p}><path d="M4 9 H7.5 L12 5 V19 L7.5 15 H4 Z" fill={c} stroke="none"/><path d="M16 9 Q18 12 16 15"/><path d="M19 7 Q22 12 19 17"/></svg>;
    case 'volume-low': return <svg {...p}><path d="M4 9 H7.5 L12 5 V19 L7.5 15 H4 Z" fill={c} stroke="none"/><path d="M16 9 Q18 12 16 15"/></svg>;
    case 'volume-mute': return <svg {...p}><path d="M4 9 H7.5 L12 5 V19 L7.5 15 H4 Z" fill={c} stroke="none"/><path d="M16 9 L21 14 M21 9 L16 14"/></svg>;
    case 'search':   return <svg {...p}><circle cx="11" cy="11" r="6"/><path d="M15.5 15.5 L20 20"/></svg>;
    case 'plus':     return <svg {...p}><path d="M12 5 V19 M5 12 H19"/></svg>;
    case 'check':    return <svg {...p}><path d="M5 12.5 L10 17 L19 7"/></svg>;
    case 'chevron-right': return <svg {...p}><path d="M9 5 L16 12 L9 19"/></svg>;
    case 'chevron-down':  return <svg {...p}><path d="M5 9 L12 16 L19 9"/></svg>;
    case 'chevron-up':    return <svg {...p}><path d="M5 15 L12 8 L19 15"/></svg>;
    case 'chevron-left':  return <svg {...p}><path d="M15 5 L8 12 L15 19"/></svg>;
    case 'speaker':  return <svg {...p}><rect x="6" y="3" width="12" height="18" rx="2"/><circle cx="12" cy="14" r="3.2"/><circle cx="12" cy="7" r="0.9" fill={c} stroke="none"/></svg>;
    case 'speakers': return <svg {...p}><rect x="3" y="4" width="8" height="16" rx="1.6"/><rect x="13" y="4" width="8" height="16" rx="1.6"/><circle cx="7" cy="13" r="2"/><circle cx="17" cy="13" r="2"/></svg>;
    case 'soundbar': return <svg {...p}><rect x="2.5" y="9" width="19" height="6" rx="1.4"/><circle cx="6.5" cy="12" r="0.9" fill={c} stroke="none"/><circle cx="12" cy="12" r="0.9" fill={c} stroke="none"/><circle cx="17.5" cy="12" r="0.9" fill={c} stroke="none"/></svg>;
    case 'group':    return <svg {...p}><circle cx="8" cy="9" r="3"/><circle cx="16" cy="9" r="3"/><path d="M3 19 Q3 14 8 14 Q11 14 12 16 Q13 14 16 14 Q21 14 21 19"/></svg>;
    case 'queue':    return <svg {...p}><path d="M4 6 H16 M4 12 H16 M4 18 H12"/><path d="M19 14 L22 17 L19 20" fill={c} stroke="none"/></svg>;
    case 'moon':     return <svg {...p}><path d="M19 14.5 A8 8 0 1 1 9.5 5 A6 6 0 0 0 19 14.5 Z"/></svg>;
    case 'mic':      return <svg {...p}><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 12 Q5 19 12 19 Q19 19 19 12 M12 19 V22"/></svg>;
    case 'sliders':  return <svg {...p}><path d="M4 6 H20 M4 12 H20 M4 18 H20"/><circle cx="9" cy="6" r="2" fill={T.surface}/><circle cx="15" cy="12" r="2" fill={T.surface}/><circle cx="7" cy="18" r="2" fill={T.surface}/></svg>;
    case 'wave':     return <svg {...p}><path d="M3 12 Q5 7 7 12 T11 12 T15 12 T19 12 T21 12"/></svg>;
    case 'tv':       return <svg {...p}><rect x="3" y="4" width="18" height="13" rx="1.6"/><path d="M8 21 H16 M12 17 V21"/></svg>;
    case 'timer':    return <svg {...p}><circle cx="12" cy="13" r="7"/><path d="M12 13 V9 M9 3 H15"/></svg>;
    case 'sleep':    return <svg {...p}><path d="M14 4 H19 L14 11 H19 M5 13 H10 L5 21 H10"/></svg>;
    case 'alarm':    return <svg {...p}><circle cx="12" cy="13" r="7"/><path d="M12 9 V13 L15 15 M5 5 L3 7 M19 5 L21 7"/></svg>;
    case 'settings': return <svg {...p}><circle cx="12" cy="12" r="2.4"/><path d="M12 3 V5 M12 19 V21 M3 12 H5 M19 12 H21 M5.6 5.6 L7 7 M17 17 L18.4 18.4 M5.6 18.4 L7 17 M17 7 L18.4 5.6"/></svg>;
    case 'cast':     return <svg {...p}><path d="M3 7 V5 H21 V19 H15"/><path d="M3 11 Q8 11 11 14 Q13 17 13 21 M3 15 Q5 15 7 17 Q9 19 9 21 M3 19 Q3 21 3 21"/></svg>;
    case 'kebab':    return <svg {...p}><circle cx="12" cy="5" r="1.4" fill={c} stroke="none"/><circle cx="12" cy="12" r="1.4" fill={c} stroke="none"/><circle cx="12" cy="19" r="1.4" fill={c} stroke="none"/></svg>;
    case 'dots':     return <svg {...p}><circle cx="5" cy="12" r="1.4" fill={c} stroke="none"/><circle cx="12" cy="12" r="1.4" fill={c} stroke="none"/><circle cx="19" cy="12" r="1.4" fill={c} stroke="none"/></svg>;
    case 'x':        return <svg {...p}><path d="M5 5 L19 19 M19 5 L5 19"/></svg>;
    case 'wifi':     return <svg {...p}><path d="M2 8.5 Q12 0 22 8.5 M5 12 Q12 5 19 12 M8 15.5 Q12 11 16 15.5"/><circle cx="12" cy="19.5" r="1" fill={c} stroke="none"/></svg>;
    case 'signal':   return <svg {...p}><rect x="3"  y="14" width="3" height="6" rx="0.5" fill={c} stroke="none"/><rect x="9"  y="10" width="3" height="10" rx="0.5" fill={c} stroke="none"/><rect x="15" y="6"  width="3" height="14" rx="0.5" fill={c} stroke="none"/></svg>;
    case 'home':     return <svg {...p}><path d="M3 11 L12 3 L21 11 V20 H15 V14 H9 V20 H3 Z"/></svg>;
    case 'house':    return <svg {...p}><path d="M3 11 L12 3 L21 11 V20 H3 Z"/><path d="M9 20 V14 H15 V20"/></svg>;
    case 'pin':      return <svg {...p}><path d="M12 22 V14 M5 9 A7 7 0 0 1 19 9 C19 14 12 14 12 14 C12 14 5 14 5 9 Z"/></svg>;
    case 'eq':       return <svg {...p}><rect x="4" y="14" width="3" height="6" fill={c} stroke="none"/><rect x="10.5" y="8" width="3" height="12" fill={c} stroke="none"/><rect x="17" y="11" width="3" height="9" fill={c} stroke="none"/></svg>;
    case 'link':     return <svg {...p}><path d="M10 14 L14 10 M9 7 L11 5 A3 3 0 0 1 15 9 L13 11 M11 17 L9 19 A3 3 0 0 1 5 15 L7 13"/></svg>;
    case 'unlink':   return <svg {...p}><path d="M9 7 L11 5 A3 3 0 0 1 15 9 L13 11 M11 17 L9 19 A3 3 0 0 1 5 15 L7 13 M3 3 L21 21"/></svg>;
    case 'minus':    return <svg {...p}><path d="M5 12 H19"/></svg>;
    default: return <svg {...p}><rect x="4" y="4" width="16" height="16" rx="2"/></svg>;
  }
};

// Album art — synthesized abstract covers
const ART_VARIANTS = {
  warm: {
    bg: 'linear-gradient(135deg, #f3a26a 0%, #d65a3a 50%, #8b2a3a 100%)',
    shape: <><circle cx="100" cy="60" r="50" fill="rgba(255,240,200,0.6)"/><path d="M0 140 Q60 100 120 140 T240 140 L240 200 L0 200 Z" fill="rgba(0,0,0,0.18)"/></>,
  },
  noir: {
    bg: 'linear-gradient(160deg, #1a2233 0%, #2a3550 60%, #0f1320 100%)',
    shape: <><circle cx="55" cy="55" r="32" fill="none" stroke="rgba(255,255,255,0.4)" strokeWidth="1.2"/><circle cx="55" cy="55" r="22" fill="none" stroke="rgba(255,255,255,0.25)" strokeWidth="1"/><path d="M30 130 L100 100 L170 130" stroke="rgba(255,255,255,0.5)" strokeWidth="1.5" fill="none"/></>,
  },
  mint: {
    bg: 'linear-gradient(170deg, #d4ead9 0%, #7fb8a3 50%, #3a6f6a 100%)',
    shape: <><rect x="20" y="20" width="160" height="160" fill="none" stroke="rgba(255,255,255,0.5)" strokeWidth="1.4"/><path d="M40 100 Q100 40 160 100" stroke="rgba(20,40,40,0.4)" strokeWidth="2" fill="none"/></>,
  },
  ember: {
    bg: 'linear-gradient(145deg, #2b0a0a 0%, #6f1818 50%, #d04020 100%)',
    shape: <><circle cx="100" cy="100" r="60" fill="rgba(255,180,80,0.35)"/><circle cx="100" cy="100" r="35" fill="rgba(255,220,120,0.55)"/></>,
  },
  fog: {
    bg: 'linear-gradient(180deg, #d5d8d3 0%, #9aa39b 50%, #5b6360 100%)',
    shape: <><rect x="0" y="60" width="200" height="4" fill="rgba(20,20,20,0.18)"/><rect x="0" y="120" width="200" height="4" fill="rgba(20,20,20,0.14)"/></>,
  },
  ink: {
    bg: 'linear-gradient(170deg, #0a0a0c 0%, #1a1a22 50%, #2a2a36 100%)',
    shape: <><circle cx="140" cy="70" r="42" fill="rgba(255,255,255,0.92)"/><circle cx="140" cy="70" r="42" fill="rgba(0,0,0,0.55)" clipPath="circle(20px at 130px 60px)"/></>,
  },
  citrus: {
    bg: 'linear-gradient(140deg, #f5e08a 0%, #e9a142 60%, #7a3a14 100%)',
    shape: <><circle cx="100" cy="100" r="70" fill="none" stroke="rgba(40,20,0,0.4)" strokeWidth="2"/></>,
  },
  plum: {
    bg: 'linear-gradient(155deg, #3a1c4a 0%, #6a2d6e 50%, #c45a9a 100%)',
    shape: <><path d="M20 180 Q60 60 100 180 Q140 60 180 180" stroke="rgba(255,255,255,0.5)" strokeWidth="1.6" fill="none"/></>,
  },
};

const HFArt = ({ variant = 'warm', size = 56, radius = 8, label }) => {
  const v = ART_VARIANTS[variant] || ART_VARIANTS.warm;
  return (
    <div style={{
      width: size, height: size, borderRadius: radius, flexShrink: 0,
      background: v.bg, position:'relative', overflow:'hidden',
      boxShadow: size > 100 ? '0 12px 30px rgba(0,0,0,0.18), 0 2px 6px rgba(0,0,0,0.10)' : 'none',
    }}>
      <svg viewBox="0 0 200 200" preserveAspectRatio="xMidYMid slice" style={{position:'absolute', inset:0, width:'100%', height:'100%'}}>
        {v.shape}
      </svg>
      {label && size > 80 && (
        <div style={{position:'absolute', left: 12, bottom: 10, fontFamily: MONO,
          fontSize: 10, color:'rgba(255,255,255,0.85)', letterSpacing:'.06em'}}>{label}</div>
      )}
    </div>
  );
};

// Slider with label / value support
const HFSlider = ({ value = 0.5, h = 4, accent, showThumb = true }) => {
  const T = hfTokens();
  return (
    <div style={{position:'relative', height: h+12, display:'flex', alignItems:'center'}}>
      <div style={{flex:1, height: h, background: T.fillStrong, borderRadius: h}}/>
      <div style={{position:'absolute', left: 0, top: '50%', transform:'translateY(-50%)',
        width: `${value*100}%`, height: h, background: accent || T.ink, borderRadius: h}}/>
      {showThumb && <div style={{
        position:'absolute', left: `calc(${value*100}% - 7px)`, top:'50%',
        transform:'translateY(-50%)', width: 14, height: 14, borderRadius:'50%',
        background: T.surface, border:`1.5px solid ${accent || T.ink}`,
        boxShadow:'0 1px 3px rgba(0,0,0,0.18)',
      }}/>}
    </div>
  );
};

// Toggle
const HFToggle = ({ on }) => {
  const T = hfTokens();
  return (
    <div style={{
      width: 38, height: 22, borderRadius: 11, flexShrink:0,
      background: on ? T.accent : T.fillStrong,
      position:'relative', transition:'background .2s',
    }}>
      <div style={{
        position:'absolute', top: 2, left: on ? 18 : 2, width: 18, height: 18,
        borderRadius:'50%', background:'#fff',
        boxShadow:'0 1px 3px rgba(0,0,0,0.25)', transition:'left .2s',
      }}/>
    </div>
  );
};

// Checkbox (refined)
const HFCheck = ({ on }) => {
  const T = hfTokens();
  return (
    <div style={{
      width: 22, height: 22, borderRadius: 6, flexShrink:0,
      border: on ? `1.5px solid ${T.accent}` : `1.5px solid ${T.lineStrong}`,
      background: on ? T.accent : 'transparent',
      display:'flex', alignItems:'center', justifyContent:'center',
    }}>
      {on && <HFIcon name="check" size={14} color={T.onAccent} strokeWidth={2.4}/>}
    </div>
  );
};

// Pill / chip
const HFChip = ({ children, icon, active, style }) => {
  const T = hfTokens();
  return (
    <span style={{
      display:'inline-flex', alignItems:'center', gap: 6,
      padding:'5px 10px', borderRadius: 999,
      background: active ? T.accentSoft : T.fill,
      color: active ? T.accent : T.ink2,
      fontSize: 11.5, fontWeight: 500, whiteSpace:'nowrap',
      border: `1px solid ${active ? 'transparent' : T.line}`,
      ...style,
    }}>
      {icon && <HFIcon name={icon} size={12} color={active ? T.accent : T.inkMute} strokeWidth={1.8}/>}
      {children}
    </span>
  );
};

// Sectioned list header
const HFSectionHd = ({ children, right }) => {
  const T = hfTokens();
  return (
    <div style={{
      display:'flex', justifyContent:'space-between', alignItems:'baseline',
      padding:'0 4px 6px',
    }}>
      <span style={{fontSize: 11, fontWeight: 600, color: T.inkMute,
        letterSpacing:'.08em', textTransform:'uppercase'}}>{children}</span>
      {right}
    </div>
  );
};

// Container card
const HFCard = ({ children, style, padding = 14, onClick }) => {
  const T = hfTokens();
  return (
    <div onClick={onClick} style={{
      background: T.surface, border: `1px solid ${T.line}`,
      borderRadius: 16, padding,
      ...style,
    }}>{children}</div>
  );
};

// Setting row
const HFRow = ({ icon, label, sub, right, onClick, last, dim }) => {
  const T = hfTokens();
  return (
    <div onClick={onClick} style={{
      padding:'12px 0', display:'flex', alignItems:'center', gap: 12,
      borderBottom: last ? 'none' : `1px solid ${T.line}`,
      opacity: dim ? 0.55 : 1,
    }}>
      {icon && (
        <div style={{
          width: 32, height: 32, borderRadius: 9, background: T.fill,
          display:'flex', alignItems:'center', justifyContent:'center', flexShrink: 0,
        }}>
          <HFIcon name={icon} size={16} color={T.ink2}/>
        </div>
      )}
      <div style={{flex:1, minWidth: 0, display:'flex', flexDirection:'column', gap: 2}}>
        <span style={{fontSize: 14, fontWeight: 500, color: T.ink}}>{label}</span>
        {sub && <span style={{fontSize: 12, color: T.inkMute}}>{sub}</span>}
      </div>
      {right}
    </div>
  );
};

Object.assign(window, {
  HF, hfTokens, FONT, MONO, HFFrame, HFStatus, HFIcon, HFArt, HFSlider,
  HFToggle, HFCheck, HFChip, HFSectionHd, HFCard, HFRow,
});
