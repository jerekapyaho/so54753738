import UIKit
import AVFoundation

class InstrumentsViewController: UITableViewController {

    var engine: AVAudioEngine!
    var instrument: AVAudioUnit?
    var sequencer: AVAudioSequencer?
    
    @objc var testInstrumentAudioUnit: AUAudioUnit? // The currently selected instrument `AUAudioUnit`, if any.
    private var testInstrumentUnitNode: AVAudioUnit? // Engine's test unit node.
    
    private let availableAudioUnitsAccessQueue = DispatchQueue(label: "so54753738.availableAudioUnitsAccessQueue")
    private var _availableInstrumentAudioUnits = [AVAudioUnitComponent]()
    
    var availableInstrumentAudioUnits: [AVAudioUnitComponent] {
        get {
            var result: [AVAudioUnitComponent]!
            
            availableAudioUnitsAccessQueue.sync {
                result = self._availableInstrumentAudioUnits
            }
            
            return result
        }
        
        set {
            availableAudioUnitsAccessQueue.sync {
                self._availableInstrumentAudioUnits = newValue
            }
        }
    }
    
    @IBOutlet weak var playButton: UIBarButtonItem!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        
        playButton.isEnabled = false
        
        refreshInstrumentList()
        
        self.engine = AVAudioEngine()
        self.instrument = nil
        self.testInstrumentAudioUnit = nil
    }

    public func loadMIDIFile(_ filename: String) -> Bool {
        guard let sequencer = self.sequencer else {
            print("No sequencer available")
            return false
        }
        
        let bundle = Bundle.main
        guard let file = bundle.path(forResource: filename, ofType: "mid") else {
            print("Failed to load MIDI file '\(filename)'")
            return false
        }
        let fileURL = URL(fileURLWithPath: file)
        do {
            try sequencer.load(from: fileURL, options: AVMusicSequenceLoadOptions())
            return true
        } catch _ {
            print("Failed to load MIDI into sequencer")
        }
        return false
    }
    
    deinit {
        if let au = self.instrument {
            self.engine.disconnectNodeInput(au, bus: 0)
            self.engine.detach(au)
        }
        self.instrument = nil
        self.engine = nil
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.availableInstrumentAudioUnits.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "instrumentCell", for: indexPath)

        let audioUnit = self.availableInstrumentAudioUnits[indexPath.row]
        cell.textLabel?.text = audioUnit.name
        cell.detailTextLabel?.text = audioUnit.manufacturerName
        cell.imageView?.image = AudioComponentGetIcon(audioUnit.audioComponent, 44.0)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedInstrument = self.availableInstrumentAudioUnits[indexPath.row]

        makeAudioUnit(from: selectedInstrument) { (audioUnit: AVAudioUnit) in
            self.attachInstrument(instrument: audioUnit)
            
            if self.sequencer == nil {
                self.sequencer = AVAudioSequencer(audioEngine: self.engine)
                if self.sequencer == nil {
                    print("Couldn't create sequencer")
                    return
                }
            }

            let success = self.prepareSequencerForPlayback(sequencer: self.sequencer!, audioUnit: audioUnit)
            if success {
                print("Sequencer was prepared for playback")
            }
            else {
                print("Couldn't prepare sequencer for playback")
            }
        }
    }
    
    func prepareSequencerForPlayback(sequencer: AVAudioSequencer, audioUnit: AVAudioUnit) -> Bool {
        // AVAudioSequencer's `tracks` is a get-only property, so can't append tracks.
        // Load a MIDI file from our bundle instead.
        let success = self.loadMIDIFile("Scale")
        if success {
            print("MIDI file loaded, sequencer now has \(sequencer.tracks.count) tracks")
            
            sequencer.tracks[0].destinationAudioUnit = audioUnit
            print("Destination Audio Unit for sequencer track 0 was set to \(audioUnit.name)")

            self.playButton.isEnabled = true
            return true
        }
        else {
            return false
        }
    }
    
    @IBAction func playTapped(_ sender: Any) {
        _ = play()
        
    }
    
    func play() -> Bool {
        guard let sequencer = self.sequencer else {
            print("No sequencer available for playback")
            return false
        }
        
        self.engine.prepare()
        _ = startAudioEngine()
        
        sequencer.currentPositionInSeconds = 0
        sequencer.prepareToPlay()
        
        do {
            try sequencer.start()
            print("Sequencer started")
        }
        catch let error {
            print(error)
            return false
        }
        
        return true
    }
    
    public func startAudioEngine() -> Bool {
        do {
            try engine.start()
            print("Audio engine started, graph = \n\(String(describing: engine))")
            return true
        }
        catch let error {
            print("Unable to start audio engine, error = \(error)")
            return false
        }
    }
    
    public func stopAudioEngine() {
        self.engine.stop()
    }
    
    func refreshInstrumentList() {
        DispatchQueue.global(qos: .default).async {
            var componentDescription = AudioComponentDescription()
            componentDescription.componentType = kAudioUnitType_MusicDevice
            componentDescription.componentSubType = 0
            componentDescription.componentManufacturer = 0
            componentDescription.componentFlags = 0
            componentDescription.componentFlagsMask = 0
            
            self.availableInstrumentAudioUnits = AVAudioUnitComponentManager.shared().components(matching: componentDescription)
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    private func makeAudioUnit(from component: AVAudioUnitComponent, completion: @escaping (_ audioUnit: AVAudioUnit) -> Void) {
        let description = component.audioComponentDescription
        AVAudioUnit.instantiate(with: description, options: []) { audioUnit, error in
            guard let audioUnit = audioUnit else {
                print("Unable to instantiate instrument Audio Unit, error = \(String(describing: error))")
                return
            }
            
            completion(audioUnit)
        }
    }
    
    private func detachInstrument() {
        // Get the previously attached node, if any
        if self.testInstrumentUnitNode != nil {
            // Break testInstrumentUnitNode -> mixer connection
            engine.disconnectNodeInput(engine.mainMixerNode)
            
            // We're done with the unit; release all references.
            engine.detach(testInstrumentUnitNode!)
            
            testInstrumentUnitNode = nil
            testInstrumentAudioUnit = nil
        }
    }
    
    func attachInstrument(instrument: AVAudioUnit) {
        detachInstrument()
        let mixer = self.engine.mainMixerNode
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareFormat.sampleRate, channels: 2)
        engine.connect(mixer, to: engine.outputNode, format: stereoFormat)
        
        self.instrument = instrument  // save the current instrument node
        
        // Important to do this here, before the audio unit is attached
        self.testInstrumentAudioUnit = instrument.auAudioUnit
        
        print("Attaching instrument Audio Unit node '\(instrument.name)'")
        self.testInstrumentUnitNode = instrument
        self.engine.attach(instrument)
        
        self.engine.connect(self.instrument!, to: mixer, format: stereoFormat)
        self.instrument!.auAudioUnit.contextName = "so54753738"
        
        print("After attaching instrument Audio Unit, audio engine:\n\(String(describing: self.engine))")
    }
}
