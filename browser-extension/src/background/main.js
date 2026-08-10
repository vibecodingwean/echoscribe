import { getExtensionApi } from '../shared/browser-api.js';
import { createOrchestrator } from './orchestrator.js';
import { installBackground } from './service-worker.js';

const api = getExtensionApi();
const orchestrator = createOrchestrator({ api });
installBackground({ api, orchestrator });
