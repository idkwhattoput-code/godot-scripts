# Godot 3D Scripts Collection

A comprehensive collection of reusable scripts for 3D game development in Godot Engine. These scripts cover various aspects of game development from player controllers to optimization systems.

## Directory Structure

### 📁 player_controllers/
- **first_person_controller.gd** - Complete FPS controller with sprint, crouch, head bob
- **third_person_controller.gd** - Third-person controller with camera follow and animations

### 📁 camera_controllers/
- **orbit_camera.gd** - Smooth orbiting camera for RTS/strategy games
- **camera_shake.gd** - Advanced camera shake with multiple shake types

### 📁 physics/
- **physics_pickup.gd** - Pick up and throw physics objects
- **projectile.gd** - Configurable projectile system for bullets, arrows, grenades

### 📁 lighting/
- **dynamic_day_night.gd** - Complete day/night cycle with sun/moon movement

### 📁 particles/
- **fire_system.gd** - Realistic fire with smoke, embers, and damage

### 📁 spawners/
- **wave_spawner.gd** - Wave-based enemy spawning with difficulty scaling

### 📁 animation/
- **animation_state_machine.gd** - Advanced animation state management

### 📁 collision/
- **advanced_collision_handler.gd** - Detailed collision detection with slopes and stairs

### 📁 audio/
- **spatial_audio_manager.gd** - 3D audio management with occlusion and reverb zones

### 📁 procedural/
- **terrain_generator.gd** - Procedural terrain with LOD and texturing

### 📁 ui/
- **hud_3d.gd** - Complete HUD system with health bars, minimaps, and markers

### 📁 optimization/
- **lod_system.gd** - Level of Detail system for performance optimization

### 📁 utilities/
- **save_system.gd** - Complete save/load system with settings management
- **screenshot_capture.gd** - Advanced screenshot system with photo mode
- **debug_overlay.gd** - Performance metrics and debug information display

## Usage

1. Copy the desired script into your Godot project
2. Attach the script to an appropriate node type (check script comments)
3. Configure the exported variables in the Inspector
4. Some scripts require specific node setups - check the comments at the top of each script

## Script Features

### Player Controllers
- First-person and third-person movement
- Smooth camera controls
- Sprint, crouch, and jump mechanics
- Head bobbing and animations

### Physics Systems
- Object pickup and throwing
- Projectile physics with various behaviors
- Collision detection and response

### Visual Effects
- Dynamic lighting and day/night cycles
- Particle systems for fire, smoke, and more
- Camera effects and shake systems

### Game Systems
- Wave-based spawning
- Save/load functionality
- Audio management
- Performance optimization

### Developer Tools
- Debug overlay with performance metrics
- Screenshot capture with photo mode
- LOD system for optimization

## Requirements

- Godot Engine 3.x (most scripts should work with 3.3+)
- Some scripts may require specific project settings or input mappings
- Check individual script comments for specific requirements

## Input Mappings

Many scripts expect certain input actions to be defined in Project Settings. Common ones include:
- "move_forward", "move_backward", "move_left", "move_right" (WASD)
- "jump" (Space)
- "sprint" (Shift)
- "crouch" (Ctrl)
- "interact" (E)

## Contributing

Feel free to modify and extend these scripts for your projects. Each script is designed to be self-contained and customizable through exported variables.

## License

These scripts are provided as learning resources and templates. Use them freely in your projects.