import https from 'https';
import zlib from 'zlib';
import path from 'path';
import fs from 'fs';
import { spawn } from 'child_process';

console.log("begin=startup");

const progress_weights = {
	'preconvert': 10,
	'filters': 30,
	'overlay': 30,
	'concat': 10,
	'audio': 10,
	'subtitles': 10
}

let clips = 0;
let progress = {
	'preconvert': 0,
	'filters': 0,
	'overlay': 0,
	'concat': 0,
	'audio': 0,
	'subtitles': 0
}

function increaseProgress(context, index, inc = 1) {
	progress[context] += inc
	let current_progress = 0
	for (const key in progress_weights) {
		current_progress = Math.round(current_progress + ((progress_weights[key] / clips) * progress[key]))
	}
	console.log(`complete=${context}${index},progress=${current_progress}`)
}

function runFfmpeg(context, index, args) {
  return new Promise((resolve, reject) => {
    const ffmpeg = spawn('ffmpeg', args);

    ffmpeg.stdout.on('data', data => {
      // console.log(`stdout: ${data}`);
    });

    ffmpeg.stderr.on('data', data => {
      console.log(`stderr: ${data}`);
    });

    ffmpeg.on('close', code => {
    	switch (code) {
    	case 0:
    		// console.log(`complete=${context}${index}`)
    		increaseProgress(context, index)
        resolve();
    		break;
    	case 8:
    		console.log(`error=${context}${index}`)
				reject(new Error(`FFmpeg exited with code ${code} - missing filter / syntax error`));
				break;
    	case 222:
    		console.log(`error=${context}${index}`)
				reject(new Error(`FFmpeg exited with code ${code} - durationi error`));
				break;
			case 222:
    		console.log(`error=${context}${index}`)
				reject(new Error(`FFmpeg exited with code ${code} - empty subtitles`));
				break;
			case 234:
    		console.log(`error=${context}${index}`)
				reject(new Error(`FFmpeg exited with code ${code} - audio / amix error / argument size incorrect`));
				break;
			case 254:
    		console.log(`error=${context}${index}`)
				reject(new Error(`FFmpeg exited with code ${code} - file not on disk`));
				break;
			case 255:
    		console.log(`error=${context}${index}`)
				reject(new Error(`FFmpeg exited with code ${code} - cuda loading issue`));
				break;
			case null:
				console.log(`retry=${context}${index}`)
				runFfmpeg(context, index, args).then(resolve).catch(reject);
				break;
			default:
				console.log(`error=${context}${index}`)
				reject(new Error(`FFmpeg exited with code ${code}`));
				break;
    	}
    });
  });
}

async function runFfmpegChain(index, chainCommands, promises = null) {
  for (const args of chainCommands) {
  	if (promises != null) {
	  	console.log(`pending=${args[0]}${index}`)
	  	await Promise.all(promises)
	}
	console.log(`start=${args[0]}${index} - ${args[1]}`)
    await runFfmpeg(args[0], index, args[1]);
  }
}

let uploadUrl = null;

async function getBaseFullArgs() {
  return new Promise((resolve, reject) => {
    // Replace with your actual endpoint
    const url = process.env.FFMPEG_METADATA_ENDPOINT;

    https.get(url, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        try {
          // Parse JSON response
          const json = JSON.parse(data);
          uploadUrl = json.output

          // Extract and decode base64 gzipped flags
          const base64Str = json.flags;
          const buffer = Buffer.from(base64Str, 'base64');

          // Gunzip decompress
          zlib.gunzip(buffer, (err, decompressedBuffer) => {
            if (err) return reject(err);

            const result = decompressedBuffer.toString('utf-8');
            resolve(result);
          });
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

async function downloadAsset(asset) {
	return new Promise((resolve, reject) => {
		const url = process.env.FFMPEG_INPUT_FILE_PREFIX + asset
		const filePath = path.join("/tmp", path.basename(url))

		if (!fs.existsSync(filePath)) {
			https.get(url, (res) => {
			  // Create file write stream
			  const fileStream = fs.createWriteStream(filePath);

			  // Pipe response data to file
			  res.pipe(fileStream);

			  fileStream.on('finish', () => {
			    fileStream.close();
			    console.log('Download completed:', filePath);
			    resolve(filePath);
			  });
			}).on('error', (err) => {
			  console.error('Error downloading file:', err.message);
			  reject(filePath);
			});
		} else {
			resolve(filePath);
		}
	})
}

const ffmpeg_flags = await getBaseFullArgs()
const chains = {};

// console.log(ffmpeg_flags)
console.log("complete=startup");

// Begin FFMPEG Breakout
const regex_file_inputs = /-i\s+([^\s]+)/g;
const regex_filter_complex = /-filter_complex (\[[^\]]+\][^ ]*)/g;

const file_inputs_matches = [...ffmpeg_flags.matchAll(regex_file_inputs)];
const file_inputs = file_inputs_matches.map(match => match[1]);

const filter_complex_matches = ffmpeg_flags.match(regex_filter_complex)[0].replaceAll("-filter_complex ", "").split(";");

file_inputs.forEach((item, idx) => {
	if (!item.includes("=")) chains[idx] = {
		input: item,
		promises: {
			filters: [],
			transitions: []
		}
		// filters: filter_complex_matches.match(/\[1\:v\]+(.*)\[ov1\]/g)
	}
})

// PARSE FLAGS
const regex_filters = /^\[([\d]+)\:v\].*\[ov[\d]+\]$/
const regex_glprep = /^\[ov([\d]+)\].*\[glprep[\d]+\]$/
const regex_gltransition = /\[[a-z]+([\d]+)\]\[gl[a-z]+([\d]+)\]gltransition\=.*\[glout([\d]+)\]/
const regex_overlay = /\[[a-z]+([\d]+)\]\[[a-z]+([\d]+)\]overlay\=.*\[out([\d]+)\]/
const regex_gpu_scale = /hwupload\,.*?\,hwdownload/g
const regex_gpu_scale_dimensions = /w\=([\d]+)[x\:h\=]+([\d]+)/
const regex_input = /^\[[a-z0-9\:]+\]/
const regex_input_double = /^\[[a-z0-9\:]+\]\[[a-z0-9\:]+\]/
const regex_output = /\[[a-z0-9]+\]$/
const regex_audio_trim = /\[([0-9]+)\:a\].*\[a([0-9])+\]$/
const regex_overlay_frame_ranges = /gte\(t\,([\d\/\.]+)\)\*lte\(t\,([\d\/\.]+)/
const regex_gltransition_frame_ranges = /offset=([\d\.]+)\:duration=([\d\.]+)/
const regex_gltransition_offset = /offset=([\d\.]+)\:/
const regex_subtitles = /(drawtext|drawbox=.*[\d]+)\[out]/
const regex_setpts = /\,setpts\=PTS-STARTPTS\+[\d\.]+\/TB/

const regex_overlay_enable = /(enable=.*\:)x/

let audio_index = 1
let subtitles_match = ""

let HW_ACCELL_INIT = [
	"-init_hw_device",
	"cuda=primary:0",
	"-filter_hw_device",
	"primary"
]
if (process.env.USE_GPU == 0) {
	HW_ACCELL_INIT = []
}

filter_complex_matches.forEach((filter_chain) => {
	const filter_assignment = filter_chain.match(regex_filters)
	const filter_glprep = filter_chain.match(regex_glprep)
	const filter_gltransition = filter_chain.match(regex_gltransition)
	const filter_overlay = filter_chain.match(regex_overlay)
	const filter_audio_trim = filter_chain.match(regex_audio_trim)
	const filter_subtitles = filter_chain.match(regex_subtitles)

	if (filter_assignment != null) {
		// CPU Overrides
		if (process.env.USE_GPU == 0) {
			let gpu_scale_filter = filter_chain.match(regex_gpu_scale)
			// console.log(gpu_scale_filter)
			let scale_dimensions = gpu_scale_filter[0].match(regex_gpu_scale_dimensions)
			chains[filter_assignment[1]]["_filters"] = filter_chain.replaceAll(regex_gpu_scale, `scale=${scale_dimensions[1]}x${scale_dimensions[2]}`)
			// console.log("Replace scale: " + filter_chain.replaceAll(regex_gpu_scale, `scale=${scale_dimensions[1]}x${scale_dimensions[2]}`))
		} else {
			chains[filter_assignment[1]]["_filters"] = filter_chain
		}
		chains[filter_assignment[1]]["_filters"] = chains[filter_assignment[1]]["_filters"].replace(regex_input, "").replace(regex_output, "").replace(regex_setpts, "")
		// END CPU Overrides
	}
	if (filter_glprep != null) chains[filter_glprep[1]]["glprep"] = filter_chain
	if (filter_gltransition != null) {
		const gltransition_frame_ranges = filter_gltransition[0].match(regex_gltransition_frame_ranges)

		chains[filter_gltransition[3]]["overlay"] = {
			imports: filter_gltransition[1],
			filter: filter_chain.replace(regex_gltransition_offset, ""),
			glTransition: true,
			time: {
				start: gltransition_frame_ranges[1],
				end: gltransition_frame_ranges[2],
				duration: (gltransition_frame_ranges[2] - gltransition_frame_ranges[1]),
			}
		}

		if (filter_gltransition[3] == 2) {
			chains[1].overlay.time = {
				start: 0,
				end: gltransition_frame_ranges[1],
				duration: gltransition_frame_ranges[1]
			}
		} else {
			chains[(filter_gltransition[3]-1)]["overlay"].time.duration = (
				chains[(filter_gltransition[3])]["overlay"].time.start - chains[(filter_gltransition[3] - 1)]["overlay"].time.start
			)
		}

		if (!Object.hasOwn(chains[(filter_gltransition[3]-1)], "glprep")) chains[(filter_gltransition[3]-1)].glprep = "[0:v]format=rgba[glprep0]"
	}
	if (filter_overlay != null) {
		const overlay_frame_ranges = filter_chain.match(regex_overlay_frame_ranges)
		console.log({time: {
				start: overlay_frame_ranges[1],
				end: overlay_frame_ranges[2],
				duration: (overlay_frame_ranges[2] - overlay_frame_ranges[1]),
		}})
		// Inject duration into previous first clip
		if (filter_overlay[3] == 2) {
			chains[1].overlay.time = {
				start: 0,
				end: overlay_frame_ranges[1],
				duration: overlay_frame_ranges[1]
			}
		}

		chains[filter_overlay[3]]["overlay"] = {
			imports: filter_overlay[1],
			filter: [filter_overlay[0].replace(regex_input_double, "[0:v][1:v]").replace(regex_output, "[out]").replace(regex_overlay_enable, "x")],
			time: {
				start: overlay_frame_ranges[1],
				end: overlay_frame_ranges[2],
				duration: (overlay_frame_ranges[2] - overlay_frame_ranges[1]),
			}
		}
	}
	if (filter_chain.includes("[0:v]")) chains[1]["overlay"] = {
		filter: "[0:v]format=yuv420p[out]"
	}
	if (filter_audio_trim != null) {
		chains[filter_audio_trim[1]]["audioFilters"] = filter_audio_trim[0].replaceAll(`[${filter_audio_trim[1]}:a]`, `[${audio_index}:a]`).replaceAll(`[a${filter_audio_trim[1]}]`, `[a${audio_index}]`)
		audio_index = audio_index + 1
	}
	if (filter_subtitles != null) {
		subtitles_match = filter_subtitles[1]
	}
})
// END PARSE FLAGS

console.log(chains)

// STEP 1, 2: PRECONVERT & FILTERS
Object.keys(chains).forEach((input) => {
	let asset = downloadAsset(chains[input].input)
	chains[input].promises.assetDownload = [asset]
	if (!chains[input].input.includes(".mp3")) {
		clips += 1
		let duration = chains[input].overlay.time.duration
		try {
			if (duration < 0) duration = (chains[(parseInt(input) + 1)].overlay.time.start - chains[(parseInt(input) - 1)].overlay.time.end)
		} catch (error) {
			if (duration < 0) duration = 5
		}

		chains[input].overlay.time.clipDuration = duration

		let durationWithNextTransition = duration
		if (Object.hasOwn(chains[(parseInt(input) + 1)], "overlay")) {
			if (Object.hasOwn(chains[(parseInt(input) + 1)].overlay, "glTransition")) {
				durationWithNextTransition = (duration + (chains[(parseInt(input) + 1)].overlay.time.end / 2))
			} else {
			}
		}

		chains[input].overlay.time.clipWithTransitionDuration = durationWithNextTransition

		chains[input].filters = [
			["preconvert", ["-framerate", "1", "-i", ("/tmp/" + chains[input].input), "-filter_complex", "tpad=stop=-1:stop_mode=clone,fps=1,format=yuv420p", "-c:v", "libx264", "-r", "1", "-t", duration, ("/tmp/ffmpeg.preconvert."+input+".mp4"), "-y"]],
			["filters", 
				[	
					...HW_ACCELL_INIT,
					"-nostdin", 
					"-progress", 
					"pipe:1",
					"-i", 
					("/tmp/ffmpeg.preconvert."+input+".mp4"), 
					"-filter_complex", [
							"fps=60",
							chains[input]._filters, //.replaceAll("\\", "").replaceAll(/\[[\d\w\:]+\]/g, ""),
							"format=yuv420p"
						].join(","),
					"-c:v", "libx264",
					"-f", "mp4",
					"-r", "60",
					"-t", duration,
					("/tmp/ffmpeg.filters."+input+".mp4"),
					"-y"]
				]
		]
	}
	// Promise.resolve(asset)
})
// ffmpeg -nostdin -progress /dev/stderr -framerate 1 -i "/tmp/$i" -filter_complex "tpad=stop=-1:stop_mode=clone,fps=1,format=yuv420p" -c:v libx264 -r 1 -t 5 "/tmp/$i.mp4" -y 2> >(sed "s/^/[INITCONVERT${INDEX}] /") &
// STEP 1, 2: PRECONVERT & FILTERS

// STEP 3: TRANSITION / OVERLAY
const regex_gl_input = /^\[[a-z0-9]+\]\[[a-z0-9]+\]/

Object.keys(chains).forEach((input) => {
	if (Object.hasOwn(chains[input], "overlay")) {
		let duration = chains[input].overlay.time.duration
		if (duration < 0) duration = 5

		if (Object.hasOwn(chains[input].overlay, "glTransition")) {
			let imported_glprep = ""
			if (Object.hasOwn(chains[chains[input].overlay.imports], "glprep")) {
				let input_offset = chains[chains[input].overlay.imports].overlay.time.clipDuration
				imported_glprep = chains[chains[input].overlay.imports].glprep.replace(regex_input, "[0:v]")
				imported_glprep = imported_glprep.replace(regex_output, `setpts=PTS-STARTPTS+${input_offset}/TB[glprep0]`)
			} else {
				imported_glprep = "[0:v]format=rgba[glprep0]"
			}
			let local_glprep = chains[input].glprep.replace(regex_input, "[1:v]")
			local_glprep = local_glprep.replace(regex_output, "[glprep1]")

			let gltransition = chains[input].overlay.filter.replace(regex_gl_input, "[glprep0][glprep1]")
			gltransition = gltransition.replace(regex_output, "[out]")

			if (process.env.USE_CPU_DEBUG == 1) {
				const regex_gltransition_complete = /gltransition=.*\,/
				gltransition = gltransition.replace(regex_gltransition_complete, "overlay,")
			}

			chains[input].transition = [
				["overlay", [	
					...HW_ACCELL_INIT,
					"-nostdin", 
					"-progress", 
					"pipe:1",
					"-ss", (chains[chains[input].overlay.imports].overlay.time.duration - (duration / 2)),
					"-i", 
					("/tmp/ffmpeg.filters."+chains[input].overlay.imports+".mp4"), 
					"-i", 
					("/tmp/ffmpeg.filters."+input+".mp4"), 
					"-filter_complex", [
						imported_glprep,
						local_glprep,
						gltransition
					].join(";"),
					"-map", "[out]",
					"-c:v", "libx264",
					"-f", "mp4",
					"-r", "60",
					"-t", duration,
					("/tmp/ffmpeg.overlay."+input+".mp4"),
					"-y"
					]
				]
			]
		} else {
			if (Object.hasOwn(chains[input], "overlay")) {
				if (Object.hasOwn(chains[input].overlay, "imports")) {
					chains[input].transition = [
						["overlay", [	
							...HW_ACCELL_INIT,
							"-nostdin", 
							"-progress", 
							"pipe:1",
							// "-ss", (chains[chains[input].overlay.imports].overlay.time.duration - (duration / 2)), // Needed for overlays when the enable= is later.
							"-i", 
							("/tmp/ffmpeg.filters."+chains[input].overlay.imports+".mp4"), 
							"-i", 
							("/tmp/ffmpeg.filters."+input+".mp4"), 
							"-filter_complex", [
								chains[input].overlay.filter
							].join(";"),
							"-map", "[out]",
							"-c:v", "libx264",
							"-f", "mp4",
							"-r", "60",
							"-t", duration,
							("/tmp/ffmpeg.overlay."+input+".mp4"),
							"-y"
							]
						]
					]
				} else {
					chains[input].transition = [
						["overlay", [	
							...HW_ACCELL_INIT,
							"-nostdin", 
							"-progress", 
							"pipe:1",
							"-i", 
							("/tmp/ffmpeg.filters."+input+".mp4"), 
							"-filter_complex", [
								chains[input].overlay.filter
							].join(";"),
							"-map", "[out]",
							"-c:v", "libx264",
							"-f", "mp4",
							"-r", "60",
							"-t", duration,
							("/tmp/ffmpeg.overlay."+input+".mp4"),
							"-y"
							]
						]
					]
				}
			}
		}
	}
})
// STEP 3: TRANSITION / OVERLAY

// STEP 4: CONCAT
// STEP 4: CONCAT

// STEP 5: SUBTITLES + AUDIO
// STEP 5: SUBTITLES + AUDIO

console.log("** CHAIN 1 **")
Object.keys(chains).forEach((input) => {
	if (Object.hasOwn(chains[input], "filters")) {
		let flags = []
		let dependentPromises = [
			...chains[input].promises.assetDownload
		]

		chains[input].filters.forEach((filter) => {
			chains[input].promises[""]
			// console.log(filter[0])
			// console.log(filter[1].join(" "))
			flags.push(filter)
		})
		chains[input].promises.filters = [runFfmpegChain(input, flags, dependentPromises)]
	}
})

console.log("** CHAIN 2 **")

// const transitionPromiseArray = [];
const transitionPromises = [];
Object.keys(chains).forEach((input) => {
	if (Object.hasOwn(chains[input], "overlay")) {
		let transitions = []
		let dependentPromises = [
			...chains[input].promises.filters,
		]

		if (Object.hasOwn(chains[input].overlay, "imports")) {
			dependentPromises.push(...chains[chains[input].overlay.imports].promises.filters)
		}
		chains[input].transition.forEach((filter) => {
			// console.log(filter[0])
			// console.log(filter[1].join(" "))
			transitions.push(filter)

			//[runFfmpegChain([filter[1]]))
		})

		let promise = runFfmpegChain(input, transitions, dependentPromises)

		chains[input].promises.transitions = [promise]
		transitionPromises.push(promise)
	}
	// } else {
	// 	let transitions = []
	// 	let dependentPromises = [
	// 		...chains[input].promises.filters,
	// 		...chains[chains[input].overlay.imports].promises.filters
	// 	]
	// 	console.log(chains[input].overlay.imports)
	// 	console.log(chains[chains[input].overlay.imports].promises.filters)
	// 	chains[input].transition.forEach((filter) => {
	// 		// console.log(filter[0])
	// 		// console.log(filter[1].join(" "))
	// 		transitions.push(filter)

	// 		//[runFfmpegChain([filter[1]]))
	// 	})
	// 	chains[input].promises.transitions = [runFfmpegChain(input, transitions, dependentPromises)]
	// 	console.log(chains[input])
	// }
})

console.log("** CHAIN 3 **");

// console.log(chains);

(async () => {
	try {
    // await Promise.all(transitionPromises);
    
    // const inputs_concat = 

		const concat_args = [
    	"-nostdin", "-progress", "pipe:1",
    	"-f", "concat",
    	"-safe", "0",	
    	"-i", "/tmp/ffmpeg.concat.txt",
    	"-c:v", "libx264",
    	"/tmp/ffmpeg.concat.mp4",
    	"-y"
    ]

    let ffmpegSequence = [
    	["concat", concat_args],
    ]

    let prevFile = "/tmp/ffmpeg.concat.mp4"

    const audios = Object.keys(chains)
			.filter(key => 'audioFilters' in chains[key])
		  .map(key => ["-i", `/tmp/${chains[key].input}`])

		let audio_filters = Object.keys(chains)
			.filter(key => 'audioFilters' in chains[key])
		  .map(key => chains[key]['audioFilters']).join(";")

		if (audios.length > 0) {
			audio_filters += `;${[...Array(audio_index - 1).keys()].map(i => `[a${i + 1}]`).join('')}amix=inputs=${audio_index - 1}:duration=longest[aout]`
			
	    const audio_args = [
	    	"-fflags", "+genpts",
	    	"-nostdin", "-progress", "pipe:1",
	    	"-i", "/tmp/ffmpeg.concat.mp4",
	    	...audios.flat(),
	    	"-filter_complex", audio_filters,
	    	"-map", "0:v",
	    	"-map", "[aout]",
	    	"-c:v", "libx264",
	    	"/tmp/ffmpeg.audio.mp4",
	    	"-y"
	    	]

	    ffmpegSequence.push(["audio",  audio_args])
	    prevFile = "/tmp/ffmpeg.audio.mp4"
		}

    let subtitle_args = [
    	"-nostdin", "-progress", "pipe:1",
    	"-i", prevFile,
    	"-c:v", "libx264",
    	"/tmp/ffmpeg.final.mp4",
    ]
    if (subtitles_match != "") {
    	subtitle_args = [
	    	"-nostdin", "-progress", "pipe:1",
	    	"-i", prevFile,
	    	"-filter_complex_script", "/tmp/ffmpeg.subtitles.txt",
	    	"-c:v", "libx264",
	    	"/tmp/ffmpeg.final.mp4", "-y"
	    ]
    }

    ffmpegSequence.push(["subtitles", subtitle_args])

    // const subtitle_args = 

    // console.log(audio_args)

		// ffmpeg -fflags +genpts -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -i /tmp/ffmpeg_base.mp4 $AUDIOS -filter_complex "${FFMPEG_POSTMIX}" $EXTRA_MAPS ${TOTAL_DURATION} -c:v libx264 -preset veryfast -r 60 out.mov -y 2> >(sed "s/^/[final] /")

    const overlays = Object.keys(chains)
		  .map(key => `file '/tmp/ffmpeg.overlay.${key}.mp4'`)
		  .join('\n')

		transitionPromises.push(fs.writeFile("/tmp/ffmpeg.concat.txt", overlays, 'utf8', (err) => {
		  if (err) {
		    console.error('Error writing file:', err);
		  } else {
		    console.log('File written successfully');
		  }
		}))

		transitionPromises.push(fs.writeFile("/tmp/ffmpeg.subtitles.txt", subtitles_match.replace("\\", ""), 'utf8', (err) => {
		  if (err) {
		    console.error('Error writing file:', err);
		  } else {
		    console.log('File written successfully');
		  }
		}))

		if (process.env.FONT_URLS) {
			process.env.FONT_URLS.split(",").forEach((item) => {
				transitionPromises.push(spawn('curl', ["-O", item]))
			})
		}

		await runFfmpegChain("0", ffmpegSequence, transitionPromises)

		await spawn('curl', ["-T", "/tmp/ffmpeg.final.mp4", uploadUrl]);
		console.log("complete=upload")
    // await runFfmpeg("concat", 0, concat_args);
  } catch (error) {
    console.error("Promise.all rejected:", error);
    process.exit(1);
  }
})();

// console.log(chains)

// console.log(inputs_concat)

// ffmpeg -nostdin -progress /dev/stderr -f concat -safe 0 -i concat.txt -c:v libx264 /tmp/ffmpeg_base.mp4 -y 2> >(sed "s/^/[CONCAT] /")
// await Promise.all(transitionPromiseArray);
// console.log(JSON.stringify(chains, null, 2))
// End FFMPEG Breakout