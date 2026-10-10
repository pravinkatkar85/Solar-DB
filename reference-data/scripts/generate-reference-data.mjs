/**
 * Generates Solar-DB reference JSON + SQL from _source geo files and curated masters.
 * Run: node Solar-DB/reference-data/scripts/generate-reference-data.mjs
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, '_source');
const JSON_DIR = path.join(ROOT, 'json');
const SQL_DIR = path.join(ROOT, 'sql');
const SQL_SCRIPTS_DIR = path.resolve(ROOT, '..', 'SQLScripts');
const LOAD_SCRIPT = path.join(SQL_SCRIPTS_DIR, '03_seed_data.sql');

const AUDIT = {
  active_ind: true,
  created_by: 'SYSTEM',
  updated_by: 'SYSTEM',
};

function norm(s) {
  return String(s || '')
    .toLowerCase()
    .replace(/nct of /g, '')
    .replace(/&/g, 'and')
    .replace(/\(ut\)/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function esc(v) {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'boolean') return v ? 'TRUE' : 'FALSE';
  if (typeof v === 'number') return String(v);
  if (typeof v === 'object') {
    return `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb`;
  }
  return `'${String(v).replace(/'/g, "''")}'`;
}

function sqlIdentRestart(table, col) {
  return [
    'SELECT setval(',
    `  pg_get_serial_sequence('solar_app.${table}', '${col}'),`,
    `  COALESCE((SELECT MAX(${col}) FROM solar_app.${table}), 1),`,
    `  EXISTS (SELECT 1 FROM solar_app.${table})`,
    ');',
  ].join('\n');
}

const STATE_META = [
  { name: 'Andaman and Nicobar Islands', code: 'AN', gst: '35', type: 'UT', aliases: ['andaman nicobar', 'andaman and nicobar'] },
  { name: 'Andhra Pradesh', code: 'AP', gst: '37', type: 'STATE', aliases: [] },
  { name: 'Arunachal Pradesh', code: 'AR', gst: '12', type: 'STATE', aliases: [] },
  { name: 'Assam', code: 'AS', gst: '18', type: 'STATE', aliases: [] },
  { name: 'Bihar', code: 'BR', gst: '10', type: 'STATE', aliases: [] },
  { name: 'Chandigarh', code: 'CH', gst: '04', type: 'UT', aliases: [] },
  { name: 'Chhattisgarh', code: 'CG', gst: '22', type: 'STATE', aliases: [] },
  { name: 'Dadra and Nagar Haveli and Daman and Diu', code: 'DH', gst: '26', type: 'UT', aliases: ['dadra and nagar haveli', 'daman and diu', 'dnh dd'] },
  { name: 'Delhi', code: 'DL', gst: '07', type: 'UT', aliases: ['nct of delhi', 'nct delhi'] },
  { name: 'Goa', code: 'GA', gst: '30', type: 'STATE', aliases: [] },
  { name: 'Gujarat', code: 'GJ', gst: '24', type: 'STATE', aliases: [] },
  { name: 'Haryana', code: 'HR', gst: '06', type: 'STATE', aliases: [] },
  { name: 'Himachal Pradesh', code: 'HP', gst: '02', type: 'STATE', aliases: ['himachal praddesh'] },
  { name: 'Jammu and Kashmir', code: 'JK', gst: '01', type: 'UT', aliases: ['jammu kashmir'] },
  { name: 'Jharkhand', code: 'JH', gst: '20', type: 'STATE', aliases: [] },
  { name: 'Karnataka', code: 'KA', gst: '29', type: 'STATE', aliases: [] },
  { name: 'Kerala', code: 'KL', gst: '32', type: 'STATE', aliases: [] },
  { name: 'Ladakh', code: 'LA', gst: '38', type: 'UT', aliases: [] },
  { name: 'Lakshadweep', code: 'LD', gst: '31', type: 'UT', aliases: [] },
  { name: 'Madhya Pradesh', code: 'MP', gst: '23', type: 'STATE', aliases: [] },
  { name: 'Maharashtra', code: 'MH', gst: '27', type: 'STATE', aliases: [] },
  { name: 'Manipur', code: 'MN', gst: '14', type: 'STATE', aliases: [] },
  { name: 'Meghalaya', code: 'ML', gst: '17', type: 'STATE', aliases: [] },
  { name: 'Mizoram', code: 'MZ', gst: '15', type: 'STATE', aliases: [] },
  { name: 'Nagaland', code: 'NL', gst: '13', type: 'STATE', aliases: [] },
  { name: 'Odisha', code: 'OD', gst: '21', type: 'STATE', aliases: ['orissa'] },
  { name: 'Puducherry', code: 'PY', gst: '34', type: 'UT', aliases: ['pondicherry'] },
  { name: 'Punjab', code: 'PB', gst: '03', type: 'STATE', aliases: [] },
  { name: 'Rajasthan', code: 'RJ', gst: '08', type: 'STATE', aliases: [] },
  { name: 'Sikkim', code: 'SK', gst: '11', type: 'STATE', aliases: [] },
  { name: 'Tamil Nadu', code: 'TN', gst: '33', type: 'STATE', aliases: [] },
  { name: 'Telangana', code: 'TS', gst: '36', type: 'STATE', aliases: [] },
  { name: 'Tripura', code: 'TR', gst: '16', type: 'STATE', aliases: [] },
  { name: 'Uttar Pradesh', code: 'UP', gst: '09', type: 'STATE', aliases: [] },
  { name: 'Uttarakhand', code: 'UK', gst: '05', type: 'STATE', aliases: ['uttaranchal'] },
  { name: 'West Bengal', code: 'WB', gst: '19', type: 'STATE', aliases: [] },
];

const STATE_ALIAS = {};
for (const s of STATE_META) {
  STATE_ALIAS[norm(s.name)] = s.name;
  for (const a of s.aliases) STATE_ALIAS[norm(a)] = s.name;
}

function canonicalState(name) {
  return STATE_ALIAS[norm(name)] || null;
}

const CITY_DISTRICT_HINTS = {
  mumbai: 'Mumbai',
  'navi mumbai': 'Thane',
  thane: 'Thane',
  kalyan: 'Thane',
  'vasai virar': 'Palghar',
  'pimpri chinchwad': 'Pune',
  pune: 'Pune',
  nagpur: 'Nagpur',
  nashik: 'Nashik',
  aurangabad: 'Aurangabad',
  'chhatrapati sambhajinagar': 'Aurangabad',
  kolhapur: 'Kolhapur',
  solapur: 'Solapur',
  sangli: 'Sangli',
  satara: 'Satara',
  latur: 'Latur',
  amravati: 'Amravati',
  akola: 'Akola',
  jalgaon: 'Jalgaon',
  dhule: 'Dhule',
  nanded: 'Nanded',
  chandrapur: 'Chandrapur',
  panvel: 'Raigad',
  ulhasnagar: 'Thane',
  bhiwandi: 'Thane',
  malegaon: 'Nashik',
  ichalkaranji: 'Kolhapur',
  jalna: 'Jalna',
  parbhani: 'Parbhani',
  yavatmal: 'Yavatmal',
  wardha: 'Wardha',
  gondia: 'Gondia',
  beed: 'Beed',
  osmanabad: 'Osmanabad',
  dharashiv: 'Osmanabad',
  palghar: 'Palghar',
  ratnagiri: 'Ratnagiri',
  sindhudurg: 'Sindhudurg',
  alibag: 'Raigad',
  delhi: 'New Delhi',
  'new delhi': 'New Delhi',
  bengaluru: 'Bengaluru Urban',
  bangalore: 'Bengaluru Urban',
  hyderabad: 'Hyderabad',
  secunderabad: 'Hyderabad',
  chennai: 'Chennai',
  kolkata: 'Kolkata',
  howrah: 'Howrah',
  gurugram: 'Gurugram',
  gurgaon: 'Gurugram',
  noida: 'Gautam Buddha Nagar',
  ghaziabad: 'Ghaziabad',
  faridabad: 'Faridabad',
  visakhapatnam: 'Visakhapatnam',
  vijayawada: 'Ntr',
  coimbatore: 'Coimbatore',
  madurai: 'Madurai',
  jaipur: 'Jaipur',
  jodhpur: 'Jodhpur',
  lucknow: 'Lucknow',
  kanpur: 'Kanpur Nagar',
  varanasi: 'Varanasi',
  patna: 'Patna',
  ranchi: 'Ranchi',
  bhopal: 'Bhopal',
  indore: 'Indore',
  jabalpur: 'Jabalpur',
  raipur: 'Raipur',
  bhubaneswar: 'Khordha',
  cuttack: 'Cuttack',
  thiruvananthapuram: 'Thiruvananthapuram',
  kochi: 'Ernakulam',
  kozhikode: 'Kozhikode',
  chandigarh: 'Chandigarh',
  shimla: 'Shimla',
  dehradun: 'Dehradun',
  srinagar: 'Srinagar',
  jammu: 'Jammu',
  gangtok: 'Gangtok',
  panaji: 'North Goa',
  margao: 'South Goa',
  ahmedabad: 'Ahmedabad',
  ahmadabad: 'Ahmedabad',
  surat: 'Surat',
  vadodara: 'Vadodara',
  rajkot: 'Rajkot',
  pimpri: 'Pune',
};

const MH_PINCODES = {
  Ahmednagar: '414001',
  Akola: '444001',
  Amravati: '444601',
  Aurangabad: '431001',
  Beed: '431122',
  Bhandara: '441904',
  Buldhana: '443001',
  Chandrapur: '442401',
  Dhule: '424001',
  Gadchiroli: '442605',
  Gondia: '441601',
  Hingoli: '431513',
  Jalgaon: '425001',
  Jalna: '431203',
  Kolhapur: '416001',
  Latur: '413512',
  Mumbai: '400001',
  'Mumbai City': '400001',
  'Mumbai Suburban': '400050',
  Nagpur: '440001',
  Nanded: '431601',
  Nandurbar: '425412',
  Nashik: '422001',
  Osmanabad: '413501',
  Palghar: '401404',
  Parbhani: '431401',
  Pune: '411001',
  Raigad: '402301',
  Ratnagiri: '415612',
  Sangli: '416416',
  Satara: '415001',
  Sindhudurg: '416601',
  Solapur: '413001',
  Thane: '400601',
  Wardha: '442001',
  Washim: '444505',
  Yavatmal: '445001',
  Mumbai: '400001',
  'Navi Mumbai': '400703',
  'Pimpri-Chinchwad': '411018',
  'Vasai-Virar': '401202',
  Kalyan: '421301',
  Bhiwandi: '421302',
  Panvel: '410206',
  Malegaon: '423203',
  Ichalkaranji: '416115',
};

const CAPITAL_PINS = {
  'Andaman and Nicobar Islands': ['Port Blair', '744101'],
  'Andhra Pradesh': ['Amaravati', '522020'],
  'Arunachal Pradesh': ['Itanagar', '791111'],
  Assam: ['Guwahati', '781001'],
  Bihar: ['Patna', '800001'],
  Chandigarh: ['Chandigarh', '160017'],
  Chhattisgarh: ['Raipur', '492001'],
  'Dadra and Nagar Haveli and Daman and Diu': ['Daman', '396210'],
  Delhi: ['New Delhi', '110001'],
  Goa: ['Panaji', '403001'],
  Gujarat: ['Gandhinagar', '382010'],
  Haryana: ['Chandigarh', '160017'],
  'Himachal Pradesh': ['Shimla', '171001'],
  'Jammu and Kashmir': ['Srinagar', '190001'],
  Jharkhand: ['Ranchi', '834001'],
  Karnataka: ['Bengaluru', '560001'],
  Kerala: ['Thiruvananthapuram', '695001'],
  Ladakh: ['Leh', '194101'],
  Lakshadweep: ['Kavaratti', '682555'],
  'Madhya Pradesh': ['Bhopal', '462001'],
  Maharashtra: ['Mumbai', '400001'],
  Manipur: ['Imphal', '795001'],
  Meghalaya: ['Shillong', '793001'],
  Mizoram: ['Aizawl', '796001'],
  Nagaland: ['Kohima', '797001'],
  Odisha: ['Bhubaneswar', '751001'],
  Puducherry: ['Puducherry', '605001'],
  Punjab: ['Chandigarh', '160017'],
  Rajasthan: ['Jaipur', '302001'],
  Sikkim: ['Gangtok', '737101'],
  'Tamil Nadu': ['Chennai', '600001'],
  Telangana: ['Hyderabad', '500001'],
  Tripura: ['Agartala', '799001'],
  'Uttar Pradesh': ['Lucknow', '226001'],
  Uttarakhand: ['Dehradun', '248001'],
  'West Bengal': ['Kolkata', '700001'],
};

/** India DISCOMs (PFC / integrated rating universe + MH franchisees). district null = statewide. */
const DISCOMS = [
  { code: 'ED_AN', name: 'Electricity Department, Andaman and Nicobar Islands', state: 'Andaman and Nicobar Islands', district: null },
  { code: 'APEPDCL', name: 'Andhra Pradesh Eastern Power Distribution Company Limited', state: 'Andhra Pradesh', district: null },
  { code: 'APSPDCL', name: 'Andhra Pradesh Southern Power Distribution Company Limited', state: 'Andhra Pradesh', district: null },
  { code: 'APCPDCL', name: 'Andhra Pradesh Central Power Distribution Corporation Limited', state: 'Andhra Pradesh', district: null },
  { code: 'DoP_AR', name: 'Department of Power, Arunachal Pradesh', state: 'Arunachal Pradesh', district: null },
  { code: 'APDCL', name: 'Assam Power Distribution Company Limited', state: 'Assam', district: null },
  { code: 'NBPDCL', name: 'North Bihar Power Distribution Company Limited', state: 'Bihar', district: null },
  { code: 'SBPDCL', name: 'South Bihar Power Distribution Company Limited', state: 'Bihar', district: null },
  { code: 'CED', name: 'Chandigarh Electricity Department / CPDL', state: 'Chandigarh', district: null },
  { code: 'CSPDCL', name: 'Chhattisgarh State Power Distribution Company Limited', state: 'Chhattisgarh', district: null },
  { code: 'DNHDDPDCL', name: 'DNH and DD Power Distribution Corporation Limited', state: 'Dadra and Nagar Haveli and Daman and Diu', district: null },
  { code: 'BRPL', name: 'BSES Rajdhani Power Limited', state: 'Delhi', district: null },
  { code: 'BYPL', name: 'BSES Yamuna Power Limited', state: 'Delhi', district: null },
  { code: 'TPDDL', name: 'Tata Power Delhi Distribution Limited', state: 'Delhi', district: null },
  { code: 'NDMC', name: 'New Delhi Municipal Council Electricity Wing', state: 'Delhi', district: null },
  { code: 'GED', name: 'Goa Electricity Department', state: 'Goa', district: null },
  { code: 'DGVCL', name: 'Dakshin Gujarat Vij Company Limited', state: 'Gujarat', district: null },
  { code: 'MGVCL', name: 'Madhya Gujarat Vij Company Limited', state: 'Gujarat', district: null },
  { code: 'PGVCL', name: 'Paschim Gujarat Vij Company Limited', state: 'Gujarat', district: null },
  { code: 'UGVCL', name: 'Uttar Gujarat Vij Company Limited', state: 'Gujarat', district: null },
  { code: 'TPL_AMD', name: 'Torrent Power Limited - Ahmedabad', state: 'Gujarat', district: 'Ahmedabad' },
  { code: 'TPL_SUR', name: 'Torrent Power Limited - Surat', state: 'Gujarat', district: 'Surat' },
  { code: 'UHBVNL', name: 'Uttar Haryana Bijli Vitran Nigam Limited', state: 'Haryana', district: null },
  { code: 'DHBVNL', name: 'Dakshin Haryana Bijli Vitran Nigam Limited', state: 'Haryana', district: null },
  { code: 'HPSEBL', name: 'Himachal Pradesh State Electricity Board Limited', state: 'Himachal Pradesh', district: null },
  { code: 'JPDCL', name: 'Jammu Power Distribution Corporation Limited', state: 'Jammu and Kashmir', district: null },
  { code: 'KPDCL', name: 'Kashmir Power Distribution Corporation Limited', state: 'Jammu and Kashmir', district: null },
  { code: 'JBVNL', name: 'Jharkhand Bijli Vitran Nigam Limited', state: 'Jharkhand', district: null },
  { code: 'TPADL', name: 'Tata Power Ajmer / Jamshedpur distribution (JUSCO/TPADL)', state: 'Jharkhand', district: 'East Singhbum' },
  { code: 'BESCOM', name: 'Bangalore Electricity Supply Company Limited', state: 'Karnataka', district: null },
  { code: 'CHESCOM', name: 'Chamundeshwari Electricity Supply Corporation Limited', state: 'Karnataka', district: null },
  { code: 'GESCOM', name: 'Gulbarga Electricity Supply Company Limited', state: 'Karnataka', district: null },
  { code: 'HESCOM', name: 'Hubli Electricity Supply Company Limited', state: 'Karnataka', district: null },
  { code: 'MESCOM', name: 'Mangalore Electricity Supply Company Limited', state: 'Karnataka', district: null },
  { code: 'KSEBL', name: 'Kerala State Electricity Board Limited', state: 'Kerala', district: null },
  { code: 'TCED', name: 'Thrissur Corporation Electricity Department', state: 'Kerala', district: 'Thrissur' },
  { code: 'LPD_LA', name: 'Ladakh Power Development Department', state: 'Ladakh', district: null },
  { code: 'LED_LD', name: 'Lakshadweep Electricity Department', state: 'Lakshadweep', district: null },
  { code: 'MPMKVVCL', name: 'MP Madhya Kshetra Vidyut Vitaran Company Limited', state: 'Madhya Pradesh', district: null },
  { code: 'MPPOKVVCL', name: 'MP Poorv Kshetra Vidyut Vitaran Company Limited', state: 'Madhya Pradesh', district: null },
  { code: 'MPPAKVVCL', name: 'MP Paschim Kshetra Vidyut Vitaran Company Limited', state: 'Madhya Pradesh', district: null },
  { code: 'MSEDCL', name: 'Maharashtra State Electricity Distribution Company Limited (Mahavitaran)', state: 'Maharashtra', district: null },
  { code: 'BEST', name: 'Brihanmumbai Electric Supply and Transport Undertaking', state: 'Maharashtra', district: 'Mumbai' },
  { code: 'AEML', name: 'Adani Electricity Mumbai Limited', state: 'Maharashtra', district: 'Mumbai Suburban' },
  { code: 'TPML', name: 'Tata Power Mumbai Limited', state: 'Maharashtra', district: 'Mumbai' },
  { code: 'TPML_SUB', name: 'Tata Power Mumbai Limited (Suburban licensed area)', state: 'Maharashtra', district: 'Mumbai Suburban' },
  { code: 'TPL_BHIWANDI', name: 'Torrent Power Limited - Bhiwandi (MSEDCL franchisee)', state: 'Maharashtra', district: 'Thane' },
  { code: 'MSPDCL', name: 'Manipur State Power Distribution Company Limited', state: 'Manipur', district: null },
  { code: 'MePDCL', name: 'Meghalaya Power Distribution Corporation Limited', state: 'Meghalaya', district: null },
  { code: 'PED_MZ', name: 'Power and Electricity Department, Mizoram', state: 'Mizoram', district: null },
  { code: 'DoP_NL', name: 'Department of Power, Nagaland', state: 'Nagaland', district: null },
  { code: 'TPCODL', name: 'TP Central Odisha Distribution Limited', state: 'Odisha', district: null },
  { code: 'TPNODL', name: 'TP Northern Odisha Distribution Limited', state: 'Odisha', district: null },
  { code: 'TPSODL', name: 'TP Southern Odisha Distribution Limited', state: 'Odisha', district: null },
  { code: 'TPWODL', name: 'TP Western Odisha Distribution Limited', state: 'Odisha', district: null },
  { code: 'PED_PY', name: 'Electricity Department, Puducherry', state: 'Puducherry', district: null },
  { code: 'PSPCL', name: 'Punjab State Power Corporation Limited', state: 'Punjab', district: null },
  { code: 'AVVNL', name: 'Ajmer Vidyut Vitran Nigam Limited', state: 'Rajasthan', district: null },
  { code: 'JDVVNL', name: 'Jodhpur Vidyut Vitran Nigam Limited', state: 'Rajasthan', district: null },
  { code: 'JVVNL', name: 'Jaipur Vidyut Vitran Nigam Limited', state: 'Rajasthan', district: null },
  { code: 'SPD_SK', name: 'Sikkim Power Department', state: 'Sikkim', district: null },
  { code: 'TNPDCL', name: 'Tamil Nadu Power Distribution Corporation Limited', state: 'Tamil Nadu', district: null },
  { code: 'TGNPDCL', name: 'Telangana Northern Power Distribution Company Limited', state: 'Telangana', district: null },
  { code: 'TGSPDCL', name: 'Telangana Southern Power Distribution Company Limited', state: 'Telangana', district: null },
  { code: 'TSECL', name: 'Tripura State Electricity Corporation Limited', state: 'Tripura', district: null },
  { code: 'DVVNL', name: 'Dakshinanchal Vidyut Vitran Nigam Limited', state: 'Uttar Pradesh', district: null },
  { code: 'MVVNL', name: 'Madhyanchal Vidyut Vitran Nigam Limited', state: 'Uttar Pradesh', district: null },
  { code: 'PVVNL', name: 'Paschimanchal Vidyut Vitran Nigam Limited', state: 'Uttar Pradesh', district: null },
  { code: 'PuVVNL', name: 'Purvanchal Vidyut Vitran Nigam Limited', state: 'Uttar Pradesh', district: null },
  { code: 'KESCO', name: 'Kanpur Electricity Supply Company Limited', state: 'Uttar Pradesh', district: 'Kanpur Nagar' },
  { code: 'NPCL', name: 'Noida Power Company Limited', state: 'Uttar Pradesh', district: 'Gautam Buddha Nagar' },
  { code: 'TPL_AGRA', name: 'Torrent Power Limited - Agra', state: 'Uttar Pradesh', district: 'Agra' },
  { code: 'UPCL', name: 'Uttarakhand Power Corporation Limited', state: 'Uttarakhand', district: null },
  { code: 'WBSEDCL', name: 'West Bengal State Electricity Distribution Company Limited', state: 'West Bengal', district: null },
  { code: 'CESC', name: 'CESC Limited (Kolkata)', state: 'West Bengal', district: 'Kolkata' },
  { code: 'IPCL', name: 'India Power Corporation Limited', state: 'West Bengal', district: null },
];

const REF_CATEGORIES = [
  { code: 'USER_ROLES', name: 'User Roles', desc: 'App personas' },
  { code: 'APP_LANGUAGES', name: 'App Languages', desc: 'UI language' },
  { code: 'CONNECTION_TYPES', name: 'Connection Types', desc: 'DISCOM connection class' },
  { code: 'LEAD_STATUSES', name: 'Lead Statuses', desc: 'Sales pipeline' },
  { code: 'QUOTE_STATUSES', name: 'Quote Statuses', desc: 'Quotation lifecycle' },
  { code: 'SITE_VISIT_STATUSES', name: 'Site Visit Statuses', desc: 'Scheduled through done / charges' },
  { code: 'SITE_VISIT_PURPOSES', name: 'Site Visit Purposes', desc: 'Enquiry, installation, service, complaint, commissioning' },
  { code: 'DOCUMENT_TYPES', name: 'KYC Document Types', desc: 'Onboarding checklist' },
  { code: 'DOCUMENT_VERIFICATION_STATUSES', name: 'Document Verification Statuses', desc: 'Admin review badge' },
  { code: 'EQUIPMENT_TYPES', name: 'Equipment Types', desc: 'Asset register class' },
  { code: 'EQUIPMENT_BRANDS', name: 'Equipment Brands', desc: 'Panel/inverter/battery brands' },
  { code: 'PHASE_TYPES', name: 'Phase Types', desc: 'Inverter/connection phase' },
  { code: 'STRUCTURE_TYPES', name: 'Structure Types', desc: 'Mounting structure' },
  { code: 'WARRANTY_TYPES', name: 'Warranty Types', desc: 'Warranty vault' },
  { code: 'SERVICE_TYPES', name: 'Service Types', desc: 'Preventive service booking' },
  { code: 'SERVICE_SLOT_WINDOWS', name: 'Service Slot Windows', desc: 'Morning/afternoon' },
  { code: 'SERVICE_REQUEST_STATUSES', name: 'Service Request Statuses', desc: 'AMC/cleaning request' },
  { code: 'MILESTONE_STATUSES', name: 'Free Service Milestone Statuses', desc: 'Quarterly free visits' },
  { code: 'COMPLAINT_CATEGORIES', name: 'Complaint Categories', desc: 'Ticket issue class' },
  { code: 'COMPLAINT_SEVERITIES', name: 'Complaint Severities', desc: 'Priority' },
  { code: 'TICKET_STATUSES', name: 'Ticket Statuses', desc: 'Complaint stepper' },
  { code: 'JOB_STATUSES', name: 'Job Assignment Statuses', desc: 'Technician queue' },
  { code: 'INVOICE_CATEGORIES', name: 'Invoice Categories', desc: 'Offline bill type (installation, AMC, spares, cleaning)' },
  { code: 'INVOICE_STATUSES', name: 'Invoice Statuses', desc: 'Offline bill AR status' },
  { code: 'PAYMENT_METHODS', name: 'Payment Methods', desc: 'Offline collection methods (no in-app gateway)' },
  { code: 'PAYMENT_STATUSES', name: 'Payment Statuses', desc: 'Offline payment record status' },
  { code: 'INSTALLATION_STATUSES', name: 'Installation Statuses', desc: 'Site pipeline' },
  { code: 'SITE_ACCESS_ROLES', name: 'Site Access Roles', desc: 'Multi-property access' },
  { code: 'PRODUCT_CATEGORIES', name: 'Product Catalogue Categories', desc: 'Sellable/related SKU class' },
  { code: 'PRODUCT_ENQUIRY_STATUSES', name: 'Product Enquiry Statuses', desc: 'Catalogue enquiry pipeline' },
  { code: 'USER_ACCOUNT_STATUSES', name: 'User Account Statuses', desc: 'Admin suspend/activate' },
  { code: 'ORDER_STATUSES', name: 'Order Statuses', desc: 'Admin order fulfilment' },
  { code: 'FOLLOWUP_TYPES', name: 'Follow-up Types', desc: 'Call, visit, WhatsApp, email' },
  { code: 'FOLLOWUP_STATUSES', name: 'Follow-up Statuses', desc: 'Admin task pipeline' },
  { code: 'REGISTRATION_SOURCES', name: 'Registration Sources', desc: 'Path A self-app vs Path B admin post-install' },
  { code: 'NOTIFICATION_TYPES', name: 'Notification Types', desc: 'In-app / push event catalogue' },
  { code: 'NOTIFICATION_CHANNELS', name: 'Notification Channels', desc: 'IN_APP vs PUSH (OTP SMS is separate)' },
  { code: 'NOTIFICATION_DELIVERY_STATUSES', name: 'Notification Delivery Statuses', desc: 'Push send queue' },
];

const REF_DATA = {
  USER_ROLES: [
    ['ROLE_CUSTOMER', 'End Customer', 'Residential/society/commercial owner'],
    ['ROLE_TECHNICIAN', 'Field Technician / Service Engineer', 'On-ground jobs'],
    ['ROLE_SALES_AGENT', 'Sales & Survey Agent', 'Leads and feasibility'],
    ['ROLE_ADMIN', 'System Administrator', 'Back-office'],
  ],
  APP_LANGUAGES: [
    ['LANG_EN', 'English', 'Default UI'],
    ['LANG_MR', 'Marathi', 'मराठी'],
    ['LANG_HI', 'Hindi', 'हिन्दी'],
  ],
  CONNECTION_TYPES: [
    ['CONN_RESIDENTIAL', 'Residential Individual', 'Individual residential connection'],
    ['CONN_SOCIETY', 'Housing Society', 'Group housing / RWAs'],
    ['CONN_COMMERCIAL', 'Commercial / Industrial', 'C&I rooftop'],
  ],
  LEAD_STATUSES: [
    ['LEAD_NEW', 'New', null],
    ['LEAD_CONTACTED', 'Contacted', null],
    ['LEAD_VISIT_SCHEDULED', 'Site Visit Scheduled', null],
    ['LEAD_QUOTED', 'Quoted', null],
    ['LEAD_CONVERTED', 'Converted to Customer', null],
    ['LEAD_LOST', 'Lost', null],
  ],
  QUOTE_STATUSES: [
    ['QUOTE_DRAFT', 'Draft', null],
    ['QUOTE_SENT', 'Sent', null],
    ['QUOTE_ACCEPTED', 'Accepted', null],
    ['QUOTE_EXPIRED', 'Expired', null],
    ['QUOTE_REJECTED', 'Rejected', null],
  ],
  SITE_VISIT_STATUSES: [
    ['VISIT_SCHEDULED', 'Scheduled', null],
    ['VISIT_ASSIGNED', 'Assigned', null],
    ['VISIT_IN_PROGRESS', 'In Progress', null],
    ['VISIT_COMPLETED', 'Completed', 'Visit done; charges_received_ind set separately'],
    ['VISIT_CANCELLED', 'Cancelled', null],
    ['VISIT_NO_SHOW', 'No Show', null],
  ],
  SITE_VISIT_PURPOSES: [
    ['VISIT_ENQUIRY', 'Enquiry / feasibility', 'Pre-sale or catalogue enquiry visit'],
    ['VISIT_INSTALLATION', 'Installation', null],
    ['VISIT_SERVICE', 'Servicing', 'Preventive / AMC / free milestone'],
    ['VISIT_COMPLAINT', 'Complaint', null],
    ['VISIT_COMMISSIONING', 'Commissioning', null],
  ],
  DOCUMENT_TYPES: [
    ['DOC_AADHAAR', 'Aadhaar Card', 'Identity proof'],
    ['DOC_PAN', 'PAN Card', 'Identity proof'],
    ['DOC_ELEC_BILL', 'Latest Electricity Bill', 'Address and sanctioned load'],
    ['DOC_OWNERSHIP', 'Property Ownership / NOC', 'Tax receipt or agreement'],
    ['DOC_ROOF_PHOTO', 'Roof Site Photo (Pre-installation)', 'Site evidence'],
  ],
  DOCUMENT_VERIFICATION_STATUSES: [
    ['KYC_PENDING', 'Pending Verification', null],
    ['KYC_APPROVED', 'Approved', null],
    ['ACTION_REQUIRED', 'Action Required / Rejected', 'Requires rejection_comment'],
  ],
  EQUIPMENT_TYPES: [
    ['EQ_PANEL', 'Solar Panel', null],
    ['EQ_INVERTER', 'Inverter', null],
    ['EQ_STRUCTURE', 'Mounting Structure', null],
    ['EQ_BATTERY', 'Battery Bank', null],
    ['EQ_DONGLE', 'Monitoring Dongle', null],
    ['EQ_BOS', 'Balance of System', null],
  ],
  EQUIPMENT_BRANDS: [
    ['BR_WAAREE', 'Waaree', 'Panels'],
    ['BR_ADANI', 'Adani Solar', 'Panels'],
    ['BR_TATA', 'Tata Power Solar', 'Panels/EPC'],
    ['BR_VIKRAM', 'Vikram Solar', 'Panels'],
    ['BR_RENEW', 'RenewSys', 'Panels'],
    ['BR_GOLDI', 'Goldi Solar', 'Panels'],
    ['BR_TRINA', 'Trina Solar', 'Panels'],
    ['BR_JINKO', 'Jinko Solar', 'Panels'],
    ['BR_LONGI', 'LONGi', 'Panels'],
    ['BR_CANADIAN', 'Canadian Solar', 'Panels'],
    ['BR_GROWATT', 'Growatt', 'Inverters'],
    ['BR_SUNGROW', 'Sungrow', 'Inverters'],
    ['BR_SMA', 'SMA', 'Inverters'],
    ['BR_SOLIS', 'Ginlong Solis', 'Inverters'],
    ['BR_LUMINOUS', 'Luminous', 'Inverters/batteries'],
    ['BR_HAVELLS', 'Havells', 'Inverters'],
    ['BR_MICROTEK', 'Microtek', 'Inverters'],
    ['BR_EXIDE', 'Exide', 'Batteries'],
    ['BR_LIVGUARD', 'Livguard', 'Batteries'],
    ['BR_EASTMAN', 'Eastman', 'Batteries'],
  ],
  PHASE_TYPES: [
    ['PHASE_1', 'Single Phase', null],
    ['PHASE_3', 'Three Phase', null],
  ],
  STRUCTURE_TYPES: [
    ['STR_FLUSH', 'Rooftop Flush', null],
    ['STR_GI_HIGH', 'GI High-Rise', null],
    ['STR_ELEVATED', 'Elevated MMS', null],
    ['STR_GROUND', 'Ground Mount', null],
  ],
  WARRANTY_TYPES: [
    ['WAR_PRODUCT', 'Product Warranty', 'Inverter typically 5–10 years'],
    ['WAR_PERFORMANCE', 'Linear Performance Warranty', 'Panels typically 25 years'],
    ['WAR_EXTENDED', 'Extended Warranty', null],
  ],
  SERVICE_TYPES: [
    ['SVC_CLEANING', 'Routine Panel Cleaning', null],
    ['SVC_INSPECTION', 'Complete System Inspection', null],
    ['SVC_INVERTER', 'Inverter Health Check', null],
  ],
  SERVICE_SLOT_WINDOWS: [
    ['SLOT_MORNING', 'Morning (9:00–13:00)', null],
    ['SLOT_AFTERNOON', 'Afternoon (13:00–18:00)', null],
  ],
  SERVICE_REQUEST_STATUSES: [
    ['SR_OPEN', 'Open', null],
    ['SR_ASSIGNED', 'Assigned', null],
    ['SR_IN_PROGRESS', 'In Progress', null],
    ['SR_COMPLETED', 'Completed', null],
    ['SR_CANCELLED', 'Cancelled', null],
    ['SR_LAPSED', 'Lapsed', null],
  ],
  MILESTONE_STATUSES: [
    ['MS_DUE', 'Due', null],
    ['MS_BOOKED', 'Booked', null],
    ['MS_COMPLETED', 'Completed', null],
    ['MS_LAPSED', 'Lapsed', 'Not claimed within 30 days of due date'],
  ],
  COMPLAINT_CATEGORIES: [
    ['CMP_ZERO_GEN', 'Zero Generation / Inverter Red Light', null],
    ['CMP_PANEL_DMG', 'Physical Panel Damage', null],
    ['CMP_STRUCTURE', 'Structure Loose / Water Leakage', null],
    ['CMP_LOW_GEN', 'Generation Lower Than Expected', null],
    ['CMP_BILLING', 'Billing / App Connection Issue', null],
  ],
  COMPLAINT_SEVERITIES: [
    ['SEV_LOW', 'Low', null],
    ['SEV_MEDIUM', 'Medium', null],
    ['SEV_HIGH', 'High', null],
    ['SEV_EMERGENCY', 'Emergency', 'Sparking / fire risk'],
  ],
  TICKET_STATUSES: [
    ['TKT_RAISED', 'Ticket Raised', null],
    ['TKT_ASSIGNED', 'Assigned to Engineer', null],
    ['TKT_EN_ROUTE', 'Technician En-Route', null],
    ['TKT_ON_SITE', 'On-Site Inspection', null],
    ['TKT_PARTS', 'Parts Replaced', null],
    ['TKT_RESOLVED', 'Resolved & Closed', null],
  ],
  JOB_STATUSES: [
    ['JOB_QUEUED', 'Queued', null],
    ['JOB_ACCEPTED', 'Accepted', null],
    ['JOB_REJECTED', 'Rejected', null],
    ['JOB_RESCHEDULED', 'Rescheduled', null],
    ['JOB_IN_PROGRESS', 'In Progress', null],
    ['JOB_COMPLETED', 'Completed', null],
  ],
  INVOICE_CATEGORIES: [
    ['INV_INSTALL', 'Installation Balance', null],
    ['INV_AMC', 'AMC Subscription', null],
    ['INV_SPARE', 'Spare Part Replacement', null],
    ['INV_CLEANING', 'Routine Cleaning Fees', null],
  ],
  INVOICE_STATUSES: [
    ['INV_DRAFT', 'Draft', null],
    ['INV_UNPAID', 'Unpaid', null],
    ['INV_PARTIAL', 'Partially Paid', null],
    ['INV_PAID', 'Paid', null],
    ['INV_CANCELLED', 'Cancelled', null],
  ],
  PAYMENT_METHODS: [
    ['PAY_CASH', 'Cash (offline)', null],
    ['PAY_CHEQUE', 'Cheque (offline)', null],
    ['PAY_NEFT', 'Bank transfer NEFT/RTGS/IMPS (offline)', null],
    ['PAY_UPI_OFFLINE', 'UPI collected outside the app', null],
    ['PAY_OTHER', 'Other offline', null],
  ],
  PAYMENT_STATUSES: [
    ['PAY_RECORDED', 'Recorded', 'Admin entered offline receipt'],
    ['PAY_CANCELLED', 'Cancelled / reversed', null],
  ],
  INSTALLATION_STATUSES: [
    ['INST_LEAD', 'Lead / Survey', null],
    ['INST_KYC', 'KYC In Progress', null],
    ['INST_SANCTION', 'DISCOM Sanction', null],
    ['INST_MATERIAL', 'Material Delivered', null],
    ['INST_INSTALLED', 'Installed', null],
    ['INST_COMMISSIONED', 'Commissioned', null],
  ],
  SITE_ACCESS_ROLES: [
    ['ACCESS_OWNER', 'Owner', null],
    ['ACCESS_FAMILY', 'Family Member', null],
    ['ACCESS_OPERATOR', 'Site Operator', null],
  ],
  PRODUCT_CATEGORIES: [
    ['CAT_PANEL', 'Solar Panels', 'PV modules'],
    ['CAT_INVERTER', 'Inverters', 'On-grid / hybrid / off-grid'],
    ['CAT_STRUCTURE', 'Mounting Structures', null],
    ['CAT_BATTERY', 'Batteries & Storage', null],
    ['CAT_BOS', 'Balance of System', 'Cables, ACDB/DCDB, earthing'],
    ['CAT_ACCESSORY', 'Accessories', 'Optimizers, dongles, EV chargers'],
    ['CAT_AMC_ADDON', 'AMC & Service Add-ons', 'Related service products'],
    ['CAT_OTHER', 'Other Related Products', 'Admin-defined extras'],
  ],
  PRODUCT_ENQUIRY_STATUSES: [
    ['ENQ_OPEN', 'Open', 'New enquiry from registered user'],
    ['ENQ_IN_PROGRESS', 'In Progress', 'Sales following up'],
    ['ENQ_CONVERTED', 'Converted to Lead', 'Linked lead_id set'],
    ['ENQ_CLOSED', 'Closed', 'No further action'],
  ],
  USER_ACCOUNT_STATUSES: [
    ['ACCT_ACTIVE', 'Active', 'May log in'],
    ['ACCT_SUSPENDED', 'Suspended', 'Admin blocked login; row remains'],
  ],
  ORDER_STATUSES: [
    ['ORD_DRAFT', 'Draft', null],
    ['ORD_CONFIRMED', 'Confirmed', null],
    ['ORD_MATERIAL', 'Material Dispatched', null],
    ['ORD_INSTALLED', 'Installed', null],
    ['ORD_COMMISSIONED', 'Commissioned', null],
    ['ORD_CANCELLED', 'Cancelled', null],
  ],
  FOLLOWUP_TYPES: [
    ['FU_CALL', 'Phone Call', null],
    ['FU_VISIT', 'Site / Office Visit', null],
    ['FU_WHATSAPP', 'WhatsApp', null],
    ['FU_EMAIL', 'Email', null],
  ],
  FOLLOWUP_STATUSES: [
    ['FU_OPEN', 'Open', null],
    ['FU_DONE', 'Completed', null],
    ['FU_CANCELLED', 'Cancelled', null],
  ],
  REGISTRATION_SOURCES: [
    ['REG_SELF_APP', 'Play Store / self registration', 'Path A: catalogue enquiry'],
    ['REG_ADMIN_POST_INSTALL', 'Admin after installation', 'Path B'],
  ],
  NOTIFICATION_TYPES: [
    ['NTF_CATALOGUE_NEW', 'New catalogue product', 'Audience: registered customers (+ sales). On publish.'],
    ['NTF_ENQUIRY_NEW', 'New product enquiry', 'Audience: admin, sales.'],
    ['NTF_ENQUIRY_STATUS', 'Enquiry status', 'Audience: customer.'],
    ['NTF_ORDER_STATUS', 'Order / installation status', 'Audience: customer; admin on cancel.'],
    ['NTF_SERVICE_REMINDER', 'Service reminder', 'Audience: customer (site); technician if assigned. Milestone/AMC batch.'],
    ['NTF_SERVICE_REQUEST', 'Service request', 'Audience: admin on create; technician on assign; customer on assign/complete.'],
    ['NTF_COMPLAINT_NEW', 'New complaint', 'Audience: admin; technician when assigned.'],
    ['NTF_COMPLAINT_UPDATE', 'Complaint update', 'Audience: customer, admin, assigned technician.'],
    ['NTF_JOB_ASSIGNED', 'Job assigned', 'Audience: technician.'],
    ['NTF_KYC_STATUS', 'KYC reviewed', 'Audience: customer.'],
    ['NTF_ACCOUNT_READY', 'Account ready (Path B)', 'Audience: customer after admin post-install register.'],
    ['NTF_BILLING_UPDATE', 'Bill or payment recorded', 'Audience: customer (view-only).'],
    ['NTF_FOLLOWUP_DUE', 'Follow-up due', 'Audience: assigned admin/sales.'],
    ['NTF_SPARE_REQUEST', 'Spare-part request', 'Audience: admin.'],
    ['NTF_AMC_EXPIRY', 'AMC expiring', 'Audience: customer, admin. Batch −30/−7 days.'],
    ['NTF_SITE_VISIT_ASSIGNED', 'Site visit assigned', 'Audience: assignee (tech/sales/other) and customer if any.'],
    ['NTF_SITE_VISIT_DONE', 'Site visit completed', 'Audience: customer, admin; include chargeable vs free.'],
  ],
  NOTIFICATION_CHANNELS: [
    ['NTF_CH_IN_APP', 'In-app inbox', 'Always written with the notification row'],
    ['NTF_CH_PUSH', 'Push (FCM)', 'Requires push_token and push_notifications_enabled'],
  ],
  NOTIFICATION_DELIVERY_STATUSES: [
    ['NTF_DEL_PENDING', 'Pending', null],
    ['NTF_DEL_SENT', 'Sent', null],
    ['NTF_DEL_FAILED', 'Failed', null],
  ],
};

// Deployment-specific business rules intentionally start empty. Populate them
// only from approved configuration; do not promote former demo values to
// canonical seed data.
const BUSINESS_PARAMETERS = [];
const SUBSIDY_SCHEMES = [];
const SUBSIDY_SLABS = [];
const AMC_PLANS = [];
const TAX_RULES = [];
const OFFICE_LOCATIONS = [];
const VISIT_CHARGE_SLABS = [];

const CHECKLIST = [
  { job: 'SERVICE_REQUEST', code: 'VOC_ISC', label: 'Panel VOC / ISC voltage measurement', type: 'NUMERIC', mandatory: true },
  { job: 'SERVICE_REQUEST', code: 'ACDC_EARTH', label: 'AC/DC distribution box wiring and earthing check', type: 'BOOLEAN', mandatory: true },
  { job: 'SERVICE_REQUEST', code: 'PANEL_CLEAN', label: 'Physical panel cleaning verification', type: 'BOOLEAN', mandatory: true },
  { job: 'SERVICE_REQUEST', code: 'INV_LOGGER', label: 'Inverter firmware and Wi-Fi logger check', type: 'BOOLEAN', mandatory: true },
  { job: 'COMPLAINT', code: 'FAULT_CODE', label: 'Inverter / logger fault code recorded', type: 'TEXT', mandatory: true },
  { job: 'COMPLAINT', code: 'VOC_ISC', label: 'Panel VOC / ISC voltage measurement', type: 'NUMERIC', mandatory: true },
  { job: 'COMPLAINT', code: 'ACDC_EARTH', label: 'AC/DC distribution box wiring and earthing check', type: 'BOOLEAN', mandatory: true },
  { job: 'COMPLAINT', code: 'SAFETY', label: 'Sparking / isolation / safety check', type: 'BOOLEAN', mandatory: true },
  { job: 'COMMISSIONING', code: 'VOC_ISC', label: 'String VOC / ISC at commissioning', type: 'NUMERIC', mandatory: true },
  { job: 'COMMISSIONING', code: 'INV_COMM', label: 'Inverter commissioned and generating', type: 'BOOLEAN', mandatory: true },
  { job: 'COMMISSIONING', code: 'DONGLE', label: 'Monitoring dongle online', type: 'BOOLEAN', mandatory: true },
  { job: 'COMMISSIONING', code: 'EARTH', label: 'Earthing resistance acceptable', type: 'BOOLEAN', mandatory: true },
];

function matchDistrict(stateDistricts, cityName) {
  const n = norm(cityName);
  const hint = CITY_DISTRICT_HINTS[n];
  if (hint) {
    const h = stateDistricts.find((d) => norm(d) === norm(hint));
    if (h) return h;
  }
  const exact = stateDistricts.find((d) => norm(d) === n);
  if (exact) return exact;
  const starts = stateDistricts.find((d) => n.startsWith(norm(d)) || norm(d).startsWith(n));
  if (starts) return starts;
  const contains = stateDistricts.find((d) => n.includes(norm(d)) || norm(d).includes(n));
  if (contains) return contains;
  return null;
}

function writeJson(name, rows) {
  fs.writeFileSync(path.join(JSON_DIR, `${name}.json`), JSON.stringify(rows, null, 2), 'utf8');
}

function writeSql(file, table, cols, rows, idCol) {
  const header = [
    '-- Auto-generated. Do not edit by hand; re-run generate-reference-data.mjs',
    'SET search_path TO solar_app, public;',
    '',
  ];
  const lines = [...header];
  if (rows.length === 0) {
    lines.push(`-- No approved deployment configuration is currently defined for solar_app.${table}.`, '');
    fs.writeFileSync(path.join(SQL_DIR, file), lines.join('\n'), 'utf8');
    return;
  }
  const chunk = 80;
  for (let i = 0; i < rows.length; i += chunk) {
    const part = rows.slice(i, i + chunk);
    lines.push(`INSERT INTO solar_app.${table} (${cols.join(', ')})`);
    lines.push('OVERRIDING SYSTEM VALUE');
    lines.push('VALUES');
    part.forEach((r, idx) => {
      const vals = cols.map((c) => esc(r[c]));
      lines.push(`  (${vals.join(', ')})${idx === part.length - 1 ? '' : ','}`);
    });
    const updateColumns = cols.filter((col) => col !== idCol && col !== 'created_by');
    lines.push(`ON CONFLICT (${idCol}) DO UPDATE SET`);
    lines.push(
      updateColumns
        .map((col) => `  ${col} = EXCLUDED.${col}`)
        .concat('  updated_on = CURRENT_TIMESTAMP')
        .join(',\n') + ';',
    );
    lines.push('');
  }
  if (idCol) lines.push(sqlIdentRestart(table, idCol), '');
  fs.writeFileSync(path.join(SQL_DIR, file), lines.join('\n'), 'utf8');
}

function main() {
  fs.mkdirSync(JSON_DIR, { recursive: true });
  fs.mkdirSync(SQL_DIR, { recursive: true });
  for (const [directory, extension] of [[JSON_DIR, '.json'], [SQL_DIR, '.sql']]) {
    for (const file of fs.readdirSync(directory)) {
      if (file.endsWith(extension)) {
        fs.rmSync(path.join(directory, file));
      }
    }
  }

  const districtSrc = JSON.parse(fs.readFileSync(path.join(SRC, 'india-states-districts-latest.json'), 'utf8'));
  const citySrc = JSON.parse(fs.readFileSync(path.join(SRC, 'indian-cities.json'), 'utf8'));

  const countries = [
    {
      country_id: 1,
      country_code: 'IN',
      country_name: 'India',
      phone_code: '+91',
      national_phone_min_length: 10,
      national_phone_max_length: 10,
      national_phone_regex: '^[6-9][0-9]{9}$',
      postal_code_regex: '^[1-9][0-9]{5}$',
      tax_registration_label: 'GSTIN',
      tax_registration_regex: null,
      ...AUDIT,
    },
  ];
  const currencies = [
    {
      currency_id: 1,
      currency_code: 'INR',
      currency_name: 'Indian Rupee',
      decimal_places: 2,
      ...AUDIT,
    },
  ];

  const stateByName = new Map();
  const states = [];
  let stateId = 0;
  const orderedStates = [...STATE_META].sort((a, b) => a.name.localeCompare(b.name));
  for (const meta of orderedStates) {
    stateId += 1;
    const row = {
      state_id: stateId,
      country_id: 1,
      state_code: meta.code,
      state_name: meta.name,
      tax_region_code: meta.gst,
      ...AUDIT,
    };
    states.push(row);
    stateByName.set(meta.name, row);
  }

  const districts = [];
  const districtsByState = new Map();
  let districtId = 0;
  const srcByCanon = new Map();
  for (const block of districtSrc) {
    const canon = canonicalState(block.state);
    if (!canon) {
      console.warn('Unmapped source state', block.state);
      continue;
    }
    srcByCanon.set(canon, block.districts);
  }

  for (const st of states) {
    const list = srcByCanon.get(st.state_name) || [];
    const names = [...new Set(list.map((d) => d.trim()).filter(Boolean))].sort((a, b) => a.localeCompare(b));
    const arr = [];
    for (const name of names) {
      districtId += 1;
      const row = {
        district_id: districtId,
        state_id: st.state_id,
        state_name: st.state_name,
        district_name: name,
        ...AUDIT,
      };
      districts.push(row);
      arr.push(row);
    }
    districtsByState.set(st.state_name, arr);
  }

  const cities = [];
  const cityKey = new Set();
  let cityId = 0;

  function addCity(stateName, districtName, cityName) {
    const st = stateByName.get(stateName);
    const dist = (districtsByState.get(stateName) || []).find((d) => d.district_name === districtName);
    if (!st || !dist) return false;
    const key = `${st.state_id}|${norm(cityName)}`;
    if (cityKey.has(key)) return false;
    cityKey.add(key);
    cityId += 1;
    cities.push({
      city_id: cityId,
      district_id: dist.district_id,
      state_id: st.state_id,
      state_name: stateName,
      district_name: districtName,
      city_name: cityName,
      ...AUDIT,
    });
    return true;
  }

  let unmatchedCities = 0;
  for (const c of citySrc) {
    const stateName = canonicalState(c.state);
    if (!stateName) {
      unmatchedCities += 1;
      continue;
    }
    const dlist = (districtsByState.get(stateName) || []).map((d) => d.district_name);
    let distName = matchDistrict(dlist, c.name);
    if (!distName && dlist.length) distName = dlist[0];
    if (!distName) {
      unmatchedCities += 1;
      continue;
    }
    addCity(stateName, distName, c.name.trim());
  }

  let hqCities = 0;
  for (const d of districts) {
    const before = cities.length;
    addCity(d.state_name, d.district_name, d.district_name);
    if (cities.length > before) hqCities += 1;
  }

  const pincodes = [];
  const pinSeen = new Set();
  let pincodeId = 0;
  function addPin(code, city) {
    if (!code || !/^[1-9][0-9]{5}$/.test(code)) return;
    if (pinSeen.has(code)) return;
    pinSeen.add(code);
    pincodeId += 1;
    pincodes.push({
      pincode_id: pincodeId,
      pincode: code,
      city_id: city.city_id,
      district_id: city.district_id,
      state_id: city.state_id,
      city_name: city.city_name,
      district_name: city.district_name,
      state_name: city.state_name,
      ...AUDIT,
    });
  }

  for (const city of cities) {
    if (city.state_name === 'Maharashtra') {
      const pin = MH_PINCODES[city.city_name] || MH_PINCODES[city.district_name];
      if (pin) addPin(pin, city);
    }
  }
  for (const [stName, [capCity, pin]] of Object.entries(CAPITAL_PINS)) {
    const city =
      cities.find((c) => c.state_name === stName && norm(c.city_name) === norm(capCity)) ||
      cities.find((c) => c.state_name === stName && c.district_name && norm(c.district_name) === norm(capCity));
    if (city) addPin(pin, city);
  }

  const discoms = [];
  let discomId = 0;
  let discomSkip = 0;
  for (const d of DISCOMS) {
    const st = stateByName.get(d.state);
    if (!st) {
      discomSkip += 1;
      continue;
    }
    let district_id = null;
    let district_name = null;
    if (d.district) {
      const dist = (districtsByState.get(d.state) || []).find((x) => norm(x.district_name) === norm(d.district));
      if (!dist) {
        console.warn('DISCOM district not found', d.code, d.district, d.state);
        discomSkip += 1;
        continue;
      }
      district_id = dist.district_id;
      district_name = dist.district_name;
    }
    discomId += 1;
    discoms.push({
      discom_id: discomId,
      state_id: st.state_id,
      district_id,
      state_name: d.state,
      district_name,
      discom_code: d.code,
      discom_name: d.name,
      ...AUDIT,
    });
  }

  const categories = REF_CATEGORIES.map((c, i) => ({
    category_id: i + 1,
    category_code: c.code,
    category_name: c.name,
    category_desc: c.desc,
    sort_order: i + 1,
    ...AUDIT,
  }));
  const catByCode = Object.fromEntries(categories.map((c) => [c.category_code, c]));

  const refData = [];
  let refId = 0;
  for (const cat of categories) {
    const items = REF_DATA[cat.category_code] || [];
    items.forEach((item, idx) => {
      refId += 1;
      refData.push({
        ref_data_id: refId,
        category_id: cat.category_id,
        category_code: cat.category_code,
        data_code: item[0],
        data_value: item[1],
        data_desc: item[2],
        parent_ref_data_id: null,
        sort_order: idx + 1,
        extra_json: {},
        ...AUDIT,
      });
    });
  }

  const dropdowns = [
    { code: 'COUNTRIES', name: 'Countries', source: 'TABLE', table: 'ref_countries', value: 'country_id', label: 'country_name', parent: null, filter: null, sort: 'country_name' },
    { code: 'STATES', name: 'States', source: 'TABLE', table: 'ref_states', value: 'state_id', label: 'state_name', parent: 'COUNTRIES', filter: 'country_id', sort: 'state_name' },
    { code: 'DISTRICTS', name: 'Districts', source: 'TABLE', table: 'ref_districts', value: 'district_id', label: 'district_name', parent: 'STATES', filter: 'state_id', sort: 'district_name' },
    { code: 'CITIES', name: 'Cities', source: 'TABLE', table: 'ref_cities', value: 'city_id', label: 'city_name', parent: 'DISTRICTS', filter: 'district_id', sort: 'city_name' },
    { code: 'PINCODES', name: 'Pincodes', source: 'TABLE', table: 'ref_pincodes', value: 'pincode_id', label: 'pincode', parent: 'CITIES', filter: 'city_id', sort: 'pincode' },
    { code: 'DISCOMS', name: 'DISCOMs', source: 'TABLE', table: 'ref_discoms', value: 'discom_id', label: 'discom_name', parent: 'STATES', filter: 'state_id', sort: 'discom_name' },
    { code: 'DISCOMS_BY_DISTRICT', name: 'DISCOMs by District', source: 'TABLE', table: 'ref_discoms', value: 'discom_id', label: 'discom_name', parent: 'DISTRICTS', filter: 'district_id', sort: 'discom_name' },
    { code: 'AMC_PLANS', name: 'AMC Plans', source: 'TABLE', table: 'ref_amc_plans', value: 'amc_plan_id', label: 'plan_name', parent: null, filter: null, sort: 'plan_name' },
    { code: 'OFFICE_LOCATIONS', name: 'Office Locations', source: 'TABLE', table: 'ref_office_locations', value: 'office_location_id', label: 'office_name', parent: null, filter: null, sort: 'office_name' },
  ];
  for (const cat of categories) {
    dropdowns.push({
      code: cat.category_code,
      name: cat.category_name,
      source: 'REF_DATA',
      table: null,
      value: 'ref_data_id',
      label: 'data_value',
      parent: null,
      filter: null,
      sort: 'sort_order',
      category_code: cat.category_code,
    });
  }
  const dropdownRows = dropdowns.map((d, i) => ({
    dropdown_config_id: i + 1,
    dropdown_code: d.code,
    display_name: d.name,
    source_type: d.source,
    category_code: d.category_code || null,
    source_table: d.table,
    value_column: d.value,
    label_column: d.label,
    parent_dropdown_code: d.parent,
    parent_filter_column: d.filter,
    include_null_parent: d.code === 'DISCOMS_BY_DISTRICT',
    sort_column: d.sort,
    cache_ttl_seconds: 3600,
    ...AUDIT,
  }));

  const businessParameterRows = BUSINESS_PARAMETERS.map((row, i) => ({
    parameter_id: i + 1,
    ...row,
    ...AUDIT,
  }));
  const subsidySchemeRows = SUBSIDY_SCHEMES.map((row, i) => ({
    subsidy_scheme_id: i + 1,
    ...row,
    ...AUDIT,
  }));
  const subsidySlabRows = SUBSIDY_SLABS.map((row, i) => ({
    subsidy_slab_id: i + 1,
    ...row,
    ...AUDIT,
  }));
  const amcRows = AMC_PLANS.map((row, i) => ({
    amc_plan_id: i + 1,
    ...row,
    ...AUDIT,
  }));
  const taxRuleRows = TAX_RULES.map((row, i) => ({
    tax_rule_id: i + 1,
    ...row,
    ...AUDIT,
  }));

  const checklistRows = CHECKLIST.map((c, i) => ({
    checklist_item_id: i + 1,
    job_type: c.job,
    item_code: c.code,
    item_label: c.label,
    expected_value_type: c.type,
    is_mandatory: c.mandatory,
    sort_order: i + 1,
    ...AUDIT,
  }));

  const without = (row, keys) =>
    Object.fromEntries(Object.entries(row).filter(([key]) => !keys.includes(key)));
  const dbDistricts = districts.map((row) => without(row, ['state_name']));
  const dbCities = cities.map((row) => without(row, ['state_name', 'district_name']));
  const dbPincodes = pincodes.map((row) =>
    without(row, ['state_name', 'district_name', 'city_name']),
  );
  const dbDiscoms = discoms.map((row) => without(row, ['state_name', 'district_name']));
  const dbRefData = refData.map((row) => without(row, ['category_code']));
  const officeRows = OFFICE_LOCATIONS.map((row, i) => ({
    office_location_id: i + 1,
    ...row,
    ...AUDIT,
  }));
  const visitChargeRows = VISIT_CHARGE_SLABS.map((row, i) => ({
    visit_charge_slab_id: i + 1,
    ...row,
    ...AUDIT,
  }));

  writeJson('ref_currencies', currencies);
  writeJson('ref_countries', countries);
  writeJson('ref_states', states);
  writeJson('ref_districts', dbDistricts);
  writeJson('ref_cities', dbCities);
  writeJson('ref_pincodes', dbPincodes);
  writeJson('ref_discoms', dbDiscoms);
  writeJson('ref_data_categories', categories);
  writeJson('ref_data', dbRefData);
  writeJson('ref_dropdown_config', dropdownRows);
  writeJson('ref_business_parameters', businessParameterRows);
  writeJson('ref_subsidy_schemes', subsidySchemeRows);
  writeJson('ref_subsidy_slabs', subsidySlabRows);
  writeJson('ref_amc_plans', amcRows);
  writeJson('ref_tax_rules', taxRuleRows);
  writeJson('ref_checklist_items', checklistRows);
  writeJson('ref_office_locations', officeRows);
  writeJson('ref_visit_charge_slabs', visitChargeRows);

  writeSql('01_ref_currencies.sql', 'ref_currencies', ['currency_id', 'currency_code', 'currency_name', 'decimal_places', 'active_ind', 'created_by', 'updated_by'], currencies, 'currency_id');
  writeSql('02_ref_countries.sql', 'ref_countries', ['country_id', 'country_code', 'country_name', 'phone_code', 'national_phone_min_length', 'national_phone_max_length', 'national_phone_regex', 'postal_code_regex', 'tax_registration_label', 'tax_registration_regex', 'active_ind', 'created_by', 'updated_by'], countries, 'country_id');
  writeSql('03_ref_states.sql', 'ref_states', ['state_id', 'country_id', 'state_code', 'state_name', 'tax_region_code', 'active_ind', 'created_by', 'updated_by'], states, 'state_id');
  writeSql('04_ref_districts.sql', 'ref_districts', ['district_id', 'state_id', 'district_name', 'active_ind', 'created_by', 'updated_by'], dbDistricts, 'district_id');
  writeSql('05_ref_cities.sql', 'ref_cities', ['city_id', 'district_id', 'state_id', 'city_name', 'active_ind', 'created_by', 'updated_by'], dbCities, 'city_id');
  writeSql('06_ref_pincodes.sql', 'ref_pincodes', ['pincode_id', 'pincode', 'city_id', 'district_id', 'state_id', 'active_ind', 'created_by', 'updated_by'], dbPincodes, 'pincode_id');
  writeSql('07_ref_discoms.sql', 'ref_discoms', ['discom_id', 'state_id', 'district_id', 'discom_code', 'discom_name', 'active_ind', 'created_by', 'updated_by'], dbDiscoms, 'discom_id');
  writeSql('08_ref_data_categories.sql', 'ref_data_categories', ['category_id', 'category_code', 'category_name', 'category_desc', 'sort_order', 'active_ind', 'created_by', 'updated_by'], categories, 'category_id');
  writeSql(
    '09_ref_data.sql',
    'ref_data',
    ['ref_data_id', 'category_id', 'data_code', 'data_value', 'data_desc', 'parent_ref_data_id', 'sort_order', 'extra_json', 'active_ind', 'created_by', 'updated_by'],
    dbRefData,
    'ref_data_id',
  );
  writeSql(
    '10_ref_dropdown_config.sql',
    'ref_dropdown_config',
    ['dropdown_config_id', 'dropdown_code', 'display_name', 'source_type', 'category_code', 'source_table', 'value_column', 'label_column', 'parent_dropdown_code', 'parent_filter_column', 'include_null_parent', 'sort_column', 'cache_ttl_seconds', 'active_ind', 'created_by', 'updated_by'],
    dropdownRows,
    'dropdown_config_id',
  );
  writeSql(
    '11_ref_business_parameters.sql',
    'ref_business_parameters',
    ['parameter_id', 'parameter_code', 'parameter_name', 'value_type', 'numeric_value', 'text_value', 'boolean_value', 'json_value', 'parameter_unit', 'parameter_desc', 'admin_manageable_ind', 'effective_from', 'effective_to', 'active_ind', 'created_by', 'updated_by'],
    businessParameterRows,
    'parameter_id',
  );
  writeSql(
    '12_ref_subsidy_schemes.sql',
    'ref_subsidy_schemes',
    ['subsidy_scheme_id', 'scheme_code', 'scheme_name', 'country_id', 'state_id', 'calculation_method', 'maximum_benefit_amount', 'currency_code', 'eligibility_json', 'effective_from', 'effective_to', 'active_ind', 'created_by', 'updated_by'],
    subsidySchemeRows,
    'subsidy_scheme_id',
  );
  writeSql(
    '13_ref_subsidy_slabs.sql',
    'ref_subsidy_slabs',
    ['subsidy_slab_id', 'subsidy_scheme_id', 'connection_type_ref_data_id', 'min_capacity_kw', 'max_capacity_kw', 'rate_amount', 'rate_percent', 'sort_order', 'active_ind', 'created_by', 'updated_by'],
    subsidySlabRows,
    'subsidy_slab_id',
  );
  writeSql(
    '14_ref_amc_plans.sql',
    'ref_amc_plans',
    ['amc_plan_id', 'plan_code', 'plan_name', 'plan_desc', 'duration_months', 'includes_breakdown', 'includes_cleaning', 'free_visit_count', 'free_visit_radius_km', 'plan_price', 'currency_code', 'effective_from', 'effective_to', 'active_ind', 'created_by', 'updated_by'],
    amcRows,
    'amc_plan_id',
  );
  writeSql(
    '15_ref_tax_rules.sql',
    'ref_tax_rules',
    ['tax_rule_id', 'tax_rule_code', 'tax_group_code', 'tax_component_code', 'tax_display_name', 'country_id', 'state_id', 'tax_classification_code', 'calculation_method', 'rate_percent', 'rate_amount', 'currency_code', 'priority', 'effective_from', 'effective_to', 'active_ind', 'created_by', 'updated_by'],
    taxRuleRows,
    'tax_rule_id',
  );
  writeSql(
    '16_ref_checklist_items.sql',
    'ref_checklist_items',
    ['checklist_item_id', 'job_type', 'item_code', 'item_label', 'expected_value_type', 'is_mandatory', 'sort_order', 'active_ind', 'created_by', 'updated_by'],
    checklistRows,
    'checklist_item_id',
  );
  writeSql(
    '17_ref_office_locations.sql',
    'ref_office_locations',
    ['office_location_id', 'office_code', 'office_name', 'address_line1', 'address_line2', 'city_id', 'pincode_id', 'latitude', 'longitude', 'is_default', 'active_ind', 'created_by', 'updated_by'],
    officeRows,
    'office_location_id',
  );
  writeSql(
    '18_ref_visit_charge_slabs.sql',
    'ref_visit_charge_slabs',
    ['visit_charge_slab_id', 'visit_purpose_ref_data_id', 'min_distance_km', 'max_distance_km', 'charge_amount', 'currency_code', 'is_free_ind', 'effective_from', 'effective_to', 'sort_order', 'active_ind', 'created_by', 'updated_by'],
    visitChargeRows,
    'visit_charge_slab_id',
  );

  const sqlFiles = [
    '01_ref_currencies.sql',
    '02_ref_countries.sql',
    '03_ref_states.sql',
    '04_ref_districts.sql',
    '05_ref_cities.sql',
    '06_ref_pincodes.sql',
    '07_ref_discoms.sql',
    '08_ref_data_categories.sql',
    '09_ref_data.sql',
    '10_ref_dropdown_config.sql',
    '11_ref_business_parameters.sql',
    '12_ref_subsidy_schemes.sql',
    '13_ref_subsidy_slabs.sql',
    '14_ref_amc_plans.sql',
    '15_ref_tax_rules.sql',
    '16_ref_checklist_items.sql',
    '17_ref_office_locations.sql',
    '18_ref_visit_charge_slabs.sql',
  ];
  fs.mkdirSync(SQL_SCRIPTS_DIR, { recursive: true });
  const consolidatedSections = sqlFiles.map((file) => {
    const content = fs
      .readFileSync(path.join(SQL_DIR, file), 'utf8')
      .replace(/^-- Auto-generated\.[^\r\n]*(?:\r?\n)?/, '')
      .replace(/^SET search_path TO solar_app, public;\s*/m, '')
      .trim();
    return `-- =============================================================================\n-- Source: reference-data/sql/${file}\n-- =============================================================================\n${content}`;
  });
  fs.writeFileSync(
    LOAD_SCRIPT,
    [
      '-- Self-contained canonical reference-data load in foreign-key dependency order.',
      '-- Run after Solar-DB/SQLScripts/01_schema.sql has completed successfully.',
      '-- Generated by reference-data/scripts/generate-reference-data.mjs.',
      'BEGIN;',
      'SET LOCAL search_path TO solar_app, public;',
      '',
      ...consolidatedSections,
      '',
      'COMMIT;',
      '',
    ].join('\n'),
    'utf8',
  );

  const counts = [
    ['ref_currencies', currencies.length, 'Reference', 'ISO currency metadata; no exchange rates'],
    ['ref_countries', countries.length, 'Reference', 'India only (ISO IN, +91)'],
    ['ref_states', states.length, 'Reference', 'All 28 states + 8 UTs'],
    ['ref_districts', districts.length, 'Reference', 'igod.gov.in derived list (KTBsomen JSON)'],
    ['ref_cities', cities.length, 'Reference', `${citySrc.length} named towns + ${hqCities} district HQ rows so every district has a city`],
    ['ref_pincodes', pincodes.length, 'Reference', 'Representative: all Maharashtra HQ/major-city PINs + state/UT capitals (not full India Post directory)'],
    ['ref_discoms', discoms.length, 'Reference', `PFC/rating-universe DISCOMs; Maharashtra: MSEDCL + BEST + AEML + Tata Power + Torrent Bhiwandi`],
    ['ref_data_categories', categories.length, 'Reference', 'Dropdown category headers'],
    ['ref_data', refData.length, 'Reference', 'Generic dropdown values'],
    ['ref_dropdown_config', dropdownRows.length, 'Reference', 'Allowlisted fn_get_dropdown_data metadata'],
    ['ref_business_parameters', businessParameterRows.length, 'Deployment configuration', 'No unapproved defaults seeded'],
    ['ref_subsidy_schemes', subsidySchemeRows.length, 'Deployment configuration', 'No unapproved schemes seeded'],
    ['ref_subsidy_slabs', subsidySlabRows.length, 'Deployment configuration', 'Requires an approved parent scheme'],
    ['ref_amc_plans', amcRows.length, 'Deployment configuration', 'No unapproved prices or plans seeded'],
    ['ref_tax_rules', taxRuleRows.length, 'Deployment configuration', 'No unapproved tax rates seeded'],
    ['ref_checklist_items', checklistRows.length, 'Reference', 'Field job-sheet templates'],
    ['ref_office_locations', officeRows.length, 'Deployment configuration', 'No placeholder office seeded'],
    ['ref_visit_charge_slabs', visitChargeRows.length, 'Deployment configuration', 'No unapproved fees seeded'],
  ];
  const total = counts.reduce((n, r) => n + r[1], 0);
  const mhDistricts = districts.filter((d) => d.state_name === 'Maharashtra').length;
  const mhCities = cities.filter((c) => c.state_name === 'Maharashtra').length;
  const mhDiscoms = discoms.filter((d) => d.state_name === 'Maharashtra').length;

  const summary = `# Reference data summary

Generated by \`scripts/generate-reference-data.mjs\`.  
Schema: \`solar_app\`. Load with \`psql -U solar_app_user -d SolarDB -f ../SQLScripts/03_seed_data.sql\` after \`SQLScripts/01_schema.sql\`.

## Record counts

| Table | Records | Class | Notes |
| --- | ---: | --- | --- |
${counts.map((c) => `| \`${c[0]}\` | ${c[1]} | ${c[2]} | ${c[3]} |`).join('\n')}
| **Total** | **${total}** | | |

## Geography & DISCOM focus

| Slice | Count |
| --- | ---: |
| Country | 1 (India) |
| States / UTs | ${states.length} |
| Districts (all India) | ${districts.length} |
| Districts (Maharashtra) | ${mhDistricts} |
| Cities (all India, including district HQ rows) | ${cities.length} |
| Cities (Maharashtra) | ${mhCities} |
| DISCOMs (all India) | ${discoms.length} |
| DISCOMs (Maharashtra) | ${mhDiscoms} |
| Pincodes (representative) | ${pincodes.length} |

Maharashtra DISCOMs seeded: **MSEDCL** (statewide), **BEST** (Mumbai), **AEML** (Mumbai Suburban), **Tata Power Mumbai** (Mumbai + Suburban), **Torrent Power Bhiwandi** (Thane franchisee). Statewide DISCOMs use \`district_id = NULL\` so district cascade should also return them (\`district_id IS NULL OR district_id = :selected\`).

## Folder layout

| Path | Contents |
| --- | --- |
| \`json/*.json\` | One file per reference table (same IDs as SQL) |
| \`sql/01\`–\`18_*.sql\` | Idempotent \`INSERT ... OVERRIDING SYSTEM VALUE\` files |
| \`../SQLScripts/03_seed_data.sql\` | Self-contained transactional reference-data loader |
| \`_source/\` | Upstream geo JSON (not loaded directly) |
| \`scripts/generate-reference-data.mjs\` | Regenerator |

## Sources

- Districts: [KTBsomen/Indian-state-district-json](https://github.com/KTBsomen/Indian-state-district-json) (igod.gov.in).
- Cities: [nshntarora/Indian-Cities-JSON](https://github.com/nshntarora/Indian-Cities-JSON) plus a city row named after every district so dropdowns never go empty.
- DISCOMs: PFC Performance of Power Utilities / 14th integrated rating universe, plus Maharashtra private/franchisee utilities.
- Tax-region codes: India GST place-of-supply codes in generic \`ref_states.tax_region_code\`.

## Gaps (intentional)

- **Pincodes** are not the full India Post locality file (~19k unique PINs). Expand later if lead capture needs every PIN.
- **Himachal Praddesh** typo in the cities source is mapped to Himachal Pradesh.
- Cities dataset has no Sikkim / Ladakh / Lakshadweep towns; those states still have **district-name city** rows.
- Business parameters, subsidy rules, AMC plans/prices, tax rules, office data, and visit charges remain empty until approved deployment configuration is supplied.
- Unmatched source cities (unknown state): ${unmatchedCities}. DISCOM rows skipped: ${discomSkip}.

## Load order vs schema

Do not run these inserts until \`01_schema.sql\` creates the tables. The loader runs all files in one transaction and each populated table is upserted by its stable seed identity.
`;

  fs.writeFileSync(path.join(ROOT, 'SUMMARY.md'), summary, 'utf8');
  console.log(JSON.stringify({ total, unmatchedCities, discomSkip, hqCities, counts: Object.fromEntries(counts.map((c) => [c[0], c[1]])) }, null, 2));
}

main();
