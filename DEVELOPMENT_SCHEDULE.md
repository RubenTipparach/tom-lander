# Tom Lander Development Schedule
## 10 Levels in 3 Weeks (Jan 12 - Jan 31, 2025)

---

## PHASE 1: Feature Parity (Mon Jan 12 - Wed Jan 14)

### Day 1: Monday Jan 12 - Core Systems
| Priority | Task | Status |
|----------|------|--------|
| P0 | Ship damage visual system (hull cracks, smoke) | [ ] |
| P0 | Ship impact explosions (small hits) | [ ] |
| P0 | Big ship explosion (death sequence) | [ ] |
| P0 | Billboard smoke system for explosions | [x] |

### Day 2: Tuesday Jan 13 - Audio System
| Priority | Task | Status |
|----------|------|--------|
| P0 | Port audio_manager.lua to Love2D | [ ] |
| P0 | Port all SFX (see list below) | [ ] |
| P0 | Port all music tracks (see list below) | [ ] |
| P1 | Enemy explosion effects | [ ] |

### Day 3: Wednesday Jan 14 - Polish & Testing
| Priority | Task | Status |
|----------|------|--------|
| P0 | Integration testing all systems | [ ] |
| P0 | Fix any bugs from Days 1-2 | [ ] |
| P1 | Performance optimization pass | [ ] |
| P1 | Create internal test build | [ ] |

---

## AUDIO ASSETS TO PORT

### Sound Effects (from Picotron sfx())
| SFX ID | Description | Used In |
|--------|-------------|---------|
| 0 | Shooting/turret fire | main.lua:1790 |
| 1 | Thruster loop | main.lua:1287 (looped on channel 4) |
| 3 | Destruction/explosion | main.lua:606, 635, 1079 |
| 8 | Damage/collision impact | main.lua:1555, ship.lua:239 |

### Music Tracks (from audio_manager.lua)
| Track Name | File | Usage |
|------------|------|-------|
| intro | sfx/introsong.sfx | Cutscenes |
| level1 | sfx/firstlevelsong.sfx | Menu, Mission 1-2 |
| level2 | sfx/secondlevelsong.sfx | Mission 4 |
| hyperlevel | sfx/hyperlevel.sfx | Mission 5 |
| lastday | sfx/lastday.sfx | Mission 6+ (combat) |
| tom_lander | sfx/tom_lander.sfx | Mission 3 |
| newsong | sfx/newsong.sfx | Mission complete/death |

---

## PHASE 2: Content Creation (Thu Jan 15 - Wed Jan 21)

### Ship Development
| Ship | Description | Primary Missions |
|------|-------------|------------------|
| Ship 1 | Tom's Lander (current) | Act 1 all missions |
| Ship 2 | Fighter | Act 2 - combat focused |
| Ship 3 | Large Hauler | Act 3 - cargo capacity |
| Ship 4 | Orbital Rocket | Act 3 finale - space transport |

### Day 4: Thursday Jan 15 - Tutorial Expansion
| Task | Description |
|------|-------------|
| Tutorial 1 (existing M1) | Engine Test - hover and land |
| Tutorial 2 (NEW) | Basic flight - fly to waypoint and return |
| Tutorial 3 (NEW) | Cargo basics - pick up, carry, deliver |

### Day 5: Friday Jan 16 - Tutorial + Ship 2 Start
| Task | Description |
|------|-------------|
| Tutorial 4 (NEW) | Advanced maneuvers - tight spaces, rooftop landing |
| Ship 2: Fighter | Start model and mechanics |

### Day 6-7: Sat-Sun Jan 17-18 - Act 2 Tileset & Ship 2
| Task | Description |
|------|-------------|
| Capital city tileset | Urban buildings, riot barriers, fires |
| Canyon tileset | Rock formations, caves, rebel structures |
| Ship 2: Fighter | Fast, agile, weapons focused, low cargo |
| Fighter mechanics | Rapid fire, boost, shields |

### Day 8: Monday Jan 19 - Act 2 Missions Part 1
| Mission | Description | Mechanics |
|---------|-------------|-----------|
| A2M1: Capital Assault | All-out war in the capital streets | Heavy combat, escort |
| A2M2: VIP Rescue | Riot aftermath, rescue hostages | Combat + cargo delivery |

### Day 9: Tuesday Jan 20 - Act 2 Missions Part 2
| Mission | Description | Mechanics |
|---------|-------------|-----------|
| A2M3: Canyon Recon | Scan canyon to find rebel base | Exploration + stealth |
| A2M4: Base Assault | Lead bombing run on rebel base | Combat + bombing |
| A2M5: Mop Up | Eliminate remaining resistance | Combat waves |

### Day 10: Wednesday Jan 21 - DEMO BUILD DEADLINE
| Task | Status |
|------|--------|
| Final bug fixes | [ ] |
| Create stable build | [ ] |
| Upload to itch.io for playtest | [ ] |
| Share link for feedback | [ ] |

---

## PHASE 3: Act 3 & Finale (Thu Jan 22 - Fri Jan 31)

### Day 11-12: Thu-Fri Jan 22-23 - Ship 3 & Hauler Mechanics
| Task | Description |
|------|-------------|
| Ship 3: Hauler | Large cargo capacity, slow, defensive |
| Hauler mechanics | Multi-cargo, shield generator, slow turn |
| Space tileset | Asteroid field, stations, debris |

### Day 13-14: Sat-Sun Jan 24-25 - Act 3 Part 1
| Mission | Description |
|---------|-------------|
| A3M1: Framed | Tom framed for chairman murder, drone swarm attack |
| A3M2: Escape | Evade pursuers, find hidden ship |

### Day 15: Monday Jan 26 - Act 3 Part 2
| Mission | Description |
|---------|-------------|
| A3M3: Mass Driver | Fight to mass driver, escape to orbit |

### Day 16-17: Tue-Wed Jan 27-28 - Ship 4 & Space Combat
| Task | Description |
|------|-------------|
| Ship 4: Orbital Rocket | Large transport, space-capable |
| Space combat system | Zero-G movement, energy weapons |
| Megaship boss design | Multi-stage, weak points |

### Day 18-19: Thu-Fri Jan 29-30 - Act 3 Finale
| Mission | Description |
|---------|-------------|
| A3M4: Refugee Run | Alien revelation, collect refugees from asteroid base |
| A3M5: The Blockade | Final battle, destroy megaship, break blockade |

### Day 20: Saturday Jan 31 - ALPHA BUILD
| Task | Status |
|------|--------|
| Final polish pass | [ ] |
| All 16 missions playable | [ ] |
| Create alpha build | [ ] |
| Release announcement | [ ] |

---

## MISSION SUMMARY (16 Total)

### ACT 1: Tom's Beginning (6 missions - EXISTING)
1. Engine Test (tutorial hover)
2. Cargo Delivery (tutorial cargo)
3. Scientific Mission (rooftop pickup)
4. Ocean Rescue (water cargo)
5. Secret Weapon (weather mission)
6. Alien Invasion (combat intro)

### ACT 2: The Rebellion (5 missions - NEW)
7. Capital Assault - All-out war in the streets
8. VIP Rescue - Riot aftermath, rescue hostages
9. Canyon Recon - Find rebel base
10. Base Assault - Bomb the base
11. Mop Up - Final resistance

### ACT 3: The Truth (5 missions - NEW)
12. Framed - Drone swarm, chairman dies
13. Escape - Evade, find ship
14. Mass Driver - Fight to orbit
15. Refugee Run - Alien truth, gather refugees
16. The Blockade - Final battle, megaship boss

---

## DAILY CHECKLIST TEMPLATE

```
## Day X: [Date]

### Morning (Focus Work)
- [ ] Primary feature/mission
- [ ]

### Afternoon (Polish)
- [ ] Testing
- [ ] Bug fixes

### Evening (Planning)
- [ ] Review progress
- [ ] Plan next day
```

---

## RISK MITIGATION

| Risk | Mitigation |
|------|------------|
| Feature creep | Stick to MVP for each mission |
| Audio delay | Can ship without some audio if needed |
| Ship models | Use simple geometric shapes, polish later |
| Performance | Profile regularly, optimize hot paths |
| Burnout | Take breaks, sustainable pace |

---

## SUCCESS CRITERIA

### Demo Build (Jan 21)
- [ ] All 6 Act 1 missions playable
- [ ] Basic audio working
- [ ] Ship damage/explosions
- [ ] No game-breaking bugs

### Alpha Build (Jan 31)
- [ ] 15 missions total (Acts 1-3)
- [ ] 4 playable ships
- [ ] Full audio
- [ ] Basic story/cutscenes
- [ ] Endgame boss fight
